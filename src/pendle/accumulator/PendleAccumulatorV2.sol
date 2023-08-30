// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/base/interfaces/ILiquidityGauge.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {PendleLocker} from "src/pendle/locker/PendleLocker.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

interface IWETH {
    function deposit() external payable;
}

/// @title A contract that accumulates ETH rewards and notifies them to the LGV4
/// @author StakeDAO
contract PendleAccumulatorV2 {
    // Errors
    error DIFFERENT_LENGTH();
    error FEE_TOO_HIGH();
    error NOT_ALLOWED();
    error ZERO_ADDRESS();
    error WRONG_CLAIM();
    error NO_REWARD();
    error NOT_ALLOWED_TO_PULL();
    error NOT_DISTRIBUTOR();
    error ONGOING_PERIOD();
    error ONGOING_REWARD();

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant VE_PENDLE = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;

    // fee recipients
    address public bribeRecipient;
    address public daoRecipient;
    address public veSdtFeeProxy;
    address public votesRewardRecipient;
    uint256 public bribeFee;
    uint256 public daoFee;
    uint256 public veSdtFeeProxyFee;

    address public governance;
    address public locker = 0xD8fa8dC5aDeC503AcC5e026a98F32Ca5C1Fa289A;
    address public gauge = 0x50DC9aE51f78C593d4138263da7088A973b8184E;
    address public sdtDistributor;
    uint256 public claimerFee;
    uint256 public periodsToNotify;

    mapping(uint256 => uint256) public rewards; // period -> reward amount
    mapping(address => uint256) public canPullTokens;

    /// @notice If set, the rewards will be distributed to all the users of the gauge
    bool public distributeAllRewards;

    // Events
    event DaoFeeSet(uint256 _old, uint256 _new);
    event BribeFeeSet(uint256 _old, uint256 _new);
    event ERC20Rescued(address token, uint256 amount);
    event DaoRecipientSet(address _old, address _new);
    event VeSdtFeeProxySet(address _old, address _new);
    event GaugeSet(address oldGauge, address newGauge);
    event GovernanceSet(address oldGov, address newGov);
    event BribeRecipientSet(address _old, address _new);
    event LockerSet(address oldLocker, address newLocker);
    event VeSdtFeeProxyFeeSet(uint256 _old, uint256 _new);
    event DistributeAllRewardsSet(bool distributeAllRewards);
    event SdtDistributorUpdated(address oldDistributor, address newDistributor);
    event RewardNotified(address gauge, address tokenReward, uint256 amountNotified);

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _governance,
        address _daoRecipient, 
        address _bribeRecipient, 
        address _veSdtFeeProxy
    ) {
        governance = _governance;
        daoRecipient = _daoRecipient;
        bribeRecipient = _bribeRecipient;
        veSdtFeeProxy = _veSdtFeeProxy;
        daoFee = 500; // 5%
        bribeFee = 1000; // 10%
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Claims Eth rewards via the locker, wrap to WETH and notify it to the LGV4
    function claimForVePendle() external {
        if (locker == address(0)) revert ZERO_ADDRESS();

        // reward for 1 months
        address[] memory pools = new address[](1);
        pools[0] = VE_PENDLE;

        // split the reward in 4 weekly periods
        // charge fees once from the whole month reward
        _chargeFee(WETH, _claimReward(pools));
        periodsToNotify += 4;

        _notifyReward(WETH);
        _distributeSDT();
    }

    /// @notice Claims rewards for the voters and send to a recipient
    /// @param _pools pools to claim for 
    function claimForVoters(address[] calldata _pools) external {
        if (locker == address(0)) revert ZERO_ADDRESS();

        for (uint256 i; i < _pools.length;) {
            if (_pools[i] == VE_PENDLE) revert WRONG_CLAIM();
            unchecked {
                ++i;
            }
        }

        IERC20(WETH).transfer(votesRewardRecipient, _chargeFee(WETH, _claimReward(_pools)));

        _distributeSDT();
    }

    /// @notice Notify the reward already claimed for the current period
    /// @param _token token to notify as reward
    function notifyReward(address _token) external {
        _notifyReward(_token);
        _distributeSDT();
    }

    /// @notice Pull tokens
    /// @param _tokens tokens to pulls
    /// @param _amounts amounts to transfer to the caller
    function pullTokens(address[] memory _tokens, uint256[] memory _amounts) external {
        if (canPullTokens[msg.sender] == 0) revert NOT_ALLOWED_TO_PULL();
        if (_tokens.length != _amounts.length) revert DIFFERENT_LENGTH();
        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength;) {
            IERC20(_tokens[i]).transfer(msg.sender, _amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Claim reward for the pools
    /// @param _pools pools to claim the rewards
    function _claimReward(address[] memory _pools) internal returns (uint256 claimed) {
        uint256 balanceBefore = address(this).balance;

        PendleLocker(locker).claimRewards(address(this), _pools);

        claimed = address(this).balance - balanceBefore;
        if (claimed == 0) revert NO_REWARD();
        // Wrap Eth to WETH
        IWETH(WETH).deposit{value: claimed}();
    }

    /// @notice Reserve fees for dao, bribe and veSdtFeeProxy
    /// @param _token toke to charge fee 
    /// @param _amount amount to charge fees
    function _chargeFee(address _token, uint256 _amount) internal returns (uint256) {
        uint256 gaugeAmount = _amount;
        // dao part
        if (daoFee > 0) {
            uint256 daoAmount = (_amount * daoFee) / 10_000;
            IERC20(_token).transfer(daoRecipient, daoAmount);
            gaugeAmount -= daoAmount;
        }

        // bribe part
        if (bribeFee > 0) {
            uint256 bribeAmount = (_amount * bribeFee) / 10_000;
            IERC20(_token).transfer(bribeRecipient, bribeAmount);
            gaugeAmount -= bribeAmount;
        }

        // veSDTFeeProxy part
        if (veSdtFeeProxyFee > 0) {
            uint256 veSdtFeeProxyAmount = (_amount * veSdtFeeProxyFee) / 10_000;
            IERC20(_token).transfer(veSdtFeeProxy, veSdtFeeProxyAmount);
            gaugeAmount -= veSdtFeeProxyAmount;
        }
        // claimerFee part
        if (claimerFee > 0) {
            uint256 claimerFeeAmount = (_amount * claimerFee) / 10_000;
            IERC20(_token).transfer(msg.sender, claimerFeeAmount);
            gaugeAmount -= claimerFeeAmount;
        }
        return gaugeAmount;
    }

    /// @notice Distribute SDT if there is any
    function _distributeSDT() internal {
        if (sdtDistributor != address(0)) {
            ISDTDistributor(sdtDistributor).distribute(gauge);
        }
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    function _notifyReward(address _tokenReward) internal {
        uint256 amountToNotify;
        if (_tokenReward == WETH) {
            uint256 currentWeek = block.timestamp * 1 weeks / 1 weeks;
            if (rewards[currentWeek] != 0) revert ONGOING_REWARD();
            amountToNotify = IERC20(WETH).balanceOf(address(this)) / periodsToNotify;
            rewards[currentWeek] = amountToNotify;
            periodsToNotify--;
        } else {
            amountToNotify = IERC20(_tokenReward).balanceOf(address(this));
        }

        if (amountToNotify == 0) revert NO_REWARD();

        if (ILiquidityGauge(gauge).reward_data(_tokenReward).distributor != address(this)) revert NOT_DISTRIBUTOR();
        
        IERC20(_tokenReward).approve(gauge, amountToNotify);
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, amountToNotify);

        emit RewardNotified(gauge, _tokenReward, amountToNotify);

    }

    /// @notice Set DAO recipient
    /// @param _daoRecipient recipient address
    function setDaoRecipient(address _daoRecipient) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_daoRecipient == address(0)) revert ZERO_ADDRESS();
        emit DaoRecipientSet(daoRecipient, _daoRecipient);
        daoRecipient = _daoRecipient;
    }

    /// @notice Set Bribe recipient
    /// @param _bribeRecipient recipient address
    function setBribeRecipient(address _bribeRecipient) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_bribeRecipient == address(0)) revert ZERO_ADDRESS();
        emit BribeRecipientSet(bribeRecipient, _bribeRecipient);
        bribeRecipient = _bribeRecipient;
    }

    /// @notice Set VeSdtFeeProxy
    /// @param _veSdtFeeProxy proxy address
    function setVeSdtFeeProxy(address _veSdtFeeProxy) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_veSdtFeeProxy == address(0)) revert ZERO_ADDRESS();
        emit VeSdtFeeProxySet(veSdtFeeProxy, _veSdtFeeProxy);
        veSdtFeeProxy = _veSdtFeeProxy;
    }

    /// @notice Set fees reserved to the DAO at every claim
    /// @param _daoFee fee (100 = 1%)
    function setDaoFee(uint256 _daoFee) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_daoFee > 10_000 || _daoFee + bribeFee + veSdtFeeProxyFee > 10_000) {
            revert FEE_TOO_HIGH();
        }
        emit DaoFeeSet(daoFee, _daoFee);
        daoFee = _daoFee;
    }

    /// @notice Set fees reserved to bribes at every claim
    /// @param _bribeFee fee (100 = 1%)
    function setBribeFee(uint256 _bribeFee) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_bribeFee > 10_000 || _bribeFee + daoFee + veSdtFeeProxyFee > 10_000) revert FEE_TOO_HIGH();
        emit BribeFeeSet(bribeFee, _bribeFee);
        bribeFee = _bribeFee;
    }

    /// @notice Set fees reserved to bribes at every claim
    /// @param _veSdtFeeProxyFee fee (100 = 1%)
    function setVeSdtFeeProxyFee(uint256 _veSdtFeeProxyFee) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_veSdtFeeProxyFee > 10_000 || _veSdtFeeProxyFee + daoFee + bribeFee > 10_000) revert FEE_TOO_HIGH();
        emit VeSdtFeeProxyFeeSet(veSdtFeeProxyFee, _veSdtFeeProxyFee);
        veSdtFeeProxyFee = _veSdtFeeProxyFee;
    }

    /// @notice Sets gauge for the accumulator which will receive and distribute the rewards
    /// @dev Can be called only by the governance
    /// @param _gauge gauge address
    function setGauge(address _gauge) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_gauge == address(0)) revert ZERO_ADDRESS();
        emit GaugeSet(gauge, _gauge);
        gauge = _gauge;
    }

    /// @notice Sets SdtDistributor to distribute from the Accumulator SDT Rewards to Gauge.
    /// @dev Can be called only by the governance
    /// @param _sdtDistributor gauge address
    function setSdtDistributor(address _sdtDistributor) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_sdtDistributor == address(0)) revert ZERO_ADDRESS();

        emit SdtDistributorUpdated(sdtDistributor, _sdtDistributor);
        sdtDistributor = _sdtDistributor;
    }

    function setDistributeAllRewards(bool _distributeAllRewards) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        emit DistributeAllRewardsSet(distributeAllRewards = _distributeAllRewards);
    }

    /// @notice Allows the governance to set the new governance
    /// @dev Can be called only by the governance
    /// @param _governance governance address
    function setGovernance(address _governance) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_governance == address(0)) revert ZERO_ADDRESS();
        emit GovernanceSet(governance, _governance);
        governance = _governance;
    }

    /// @notice Allows the governance to set the locker
    /// @dev Can be called only by the governance
    /// @param _locker locker address
    function setLocker(address _locker) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_locker == address(0)) revert ZERO_ADDRESS();
        emit LockerSet(locker, _locker);
        locker = _locker;
    }

    /// @notice Allows the governance to set the claimer fee
    /// @dev Can be called only by the governance
    /// @param _claimerFee claimer fee
    function setClaimerFee(uint256 _claimerFee) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_claimerFee > 10_000) revert FEE_TOO_HIGH();
        claimerFee = _claimerFee;
    }

    function togglePullAllowance(address _user) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        canPullTokens[_user] = canPullTokens[_user] == 0 ? 1 : 0;
    }

    /// @notice A function that rescue any ERC20 token
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        IERC20(_token).transfer(_recipient, _amount);
        emit ERC20Rescued(_token, _amount);
    }

    receive() external payable {}
}
