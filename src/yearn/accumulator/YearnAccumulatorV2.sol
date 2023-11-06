// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "src/base/interfaces/IYearnStrategy.sol";
import "src/base/interfaces/ILiquidityGauge.sol";
import "src/base/interfaces/ISDTDistributor.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title A contract that accumulates YFI and dYFI rewards and notifies them to the LGV4
/// @author StakeDAO
contract YearnAccumulatorV2 {

    error GOV();
    error FEE_TOO_HIGH();
    error FUTURE_GOV();
    error ZERO_ADDRESS();

    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    IYearnStrategy public strategy;
    address public gauge;
    address public locker;
    address public sdtDistributor;
    address public governance;
    address public futureGovernance;

    // fee
    uint256 public daoFee;
    address public daoFeeRecipient;
    uint256 public liquidityFee;
    address public liquidityFeeRecipient;
    uint256 public claimerFee;

    uint256 public constant BASE_FEE = 10_000;

    event GaugeSet(address gauge);
    event ClaimerFeeSet(uint256 claimerFee);
    event DaoFeeSet(uint256 daoFee);
    event DaoFeeRecipientSet(address daoFeeRecipient);
    event ERC20Rescued(address token, uint256 amount);
    event LiquidityFeeSet(uint256 liquidityFee);
    event LiquidityFeeRecipientSet(address liquidityFeeRecipient);
    event LockerSet(address locker);
    event RewardNotified(address gauge, address tokenReward, uint256 amountNotified);
    event StrategySet(address strategy);
    event TransferGovernance(address futureGovernance);
    event GovernanceAccepted(address governance);

    modifier onlyGov() {
        if (msg.sender != governance) revert GOV();
        _;
    }

    modifier onlyFutureGov() {
        if (msg.sender != futureGovernance) revert FUTURE_GOV();
        _;
    }


    /* ========== CONSTRUCTOR ========== */
    constructor(address _gauge, address _strategy, address _daoFeeRecipient, address _liquidityFeeRecipient) {
        gauge = _gauge;
        daoFeeRecipient = _daoFeeRecipient;
        liquidityFeeRecipient = _liquidityFeeRecipient;
        strategy = IYearnStrategy(_strategy);
        locker = strategy.locker();
        governance = msg.sender;
        daoFee = 500; // 5%
        liquidityFee = 1_000; // 10%
        claimerFee = 50; // 0.5%
        IERC20(YFI).approve(gauge, type(uint256).max);
        IERC20(DYFI).approve(gauge, type(uint256).max);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Claims YFI rewards for the locker and notify an amount to the LGV4
    function claimYfiAndNotifyAll() external {
        // claim YFI reward
        strategy.claimNativeRewards();
        uint256 amount = IERC20(YFI).balanceOf(address(this));

        // charge fees 
        amount -= _chargeFee(YFI, amount);
        // notify YFI as reward in sdYFI gauge
        _notifyReward(YFI, amount);
        // notify SDT
        _distributeSDT();
    }

    /// @notice Claims DYFI rewards for the locker and notify all to the LGV4
    function claimDyfiAndNotifyAll() external {
        // claim dYFI reward
        strategy.claimDYFIRewardPool();
        uint256 amount = IERC20(DYFI).balanceOf(address(this));

        // charge fees 
        amount -= _chargeFee(DYFI, amount);
        // notify YFI as reward in sdYFI gauge
        _notifyReward(DYFI, amount);
        // notify SDT
        _distributeSDT();
    }

    /// @notice Claims YFI rewards for the locker and notify all to the LGV4
    function claimAndNotifyAll() external {
        // claim YFI reward
        strategy.claimNativeRewards();
        uint256 yfiAmount = IERC20(YFI).balanceOf(address(this));

        // claim dYFI reward
        strategy.claimDYFIRewardPool();
        uint256 dYfiAmount = IERC20(DYFI).balanceOf(address(this));

        yfiAmount -= _chargeFee(YFI, yfiAmount);
        dYfiAmount -= _chargeFee(DYFI, dYfiAmount);

        _notifyReward(YFI, yfiAmount);
        _notifyReward(DYFI, dYfiAmount);

        _distributeSDT();
    }

    /// @notice A function that rescue any ERC20 token
    /// @dev Can be called only by the governance
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external onlyGov {
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        IERC20(_token).transfer(_recipient, _amount);
        emit ERC20Rescued(_token, _amount);
    }

    /// @notice Sets the strategy to claim the DYFI reward
    /// @dev Can be called only by the governance
    /// @param _strategy strategy address
    function setStrategy(address _strategy) external onlyGov {
        if (_strategy == address(0)) revert ZERO_ADDRESS();
        strategy = IYearnStrategy(_strategy);
        emit StrategySet(_strategy);
    }

    /// @notice Sets gauge for the accumulator which will receive and distribute the rewards
    /// @dev Can be called only by the governance
    /// @param _gauge gauge address
    function setGauge(address _gauge) external onlyGov {
        if (_gauge == address(0)) revert ZERO_ADDRESS();
        gauge = _gauge;
        emit GaugeSet(gauge);
    }

    /// @notice Sets dao fee recipient
    /// @dev Can be called only by the governance
    function setDaoFeeRecipient(address _daoFeeRecipient) external onlyGov {
        emit DaoFeeRecipientSet(daoFeeRecipient = _daoFeeRecipient);
    }

    /// @notice Sets liquidity fee recipient
    /// @dev Can be called only by the governance
    function setLiquidityFeeRecipient(address _liquidityFeeRecipient) external onlyGov {
        emit LiquidityFeeRecipientSet(liquidityFeeRecipient = _liquidityFeeRecipient);
    }

    /// @notice Sets dao fee
    /// @dev Can be called only by the governance
    function setDaoFee(uint256 _daoFee) external onlyGov {
        if (_daoFee + liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit DaoFeeSet(daoFee = _daoFee);
    }

    function setLiquidityFeeRecipient(uint256 _liquidityFee) external onlyGov {
        if (daoFee + _liquidityFee + claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit LiquidityFeeSet(liquidityFee = _liquidityFee);
    }

    function setClaimerFee(uint256 _claimerFee) external onlyGov {
        if (daoFee + liquidityFee + _claimerFee > BASE_FEE) revert FEE_TOO_HIGH();
        emit ClaimerFeeSet(claimerFee = _claimerFee);
    }

    /// @notice Allows the governance to set the locker
    /// @dev Can be called only by the governance
    /// @param _locker locker address
    function setLocker(address _locker) external onlyGov {
        if (_locker == address(0)) revert ZERO_ADDRESS();
        locker = _locker;
        emit LockerSet(locker);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGov {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
        emit TransferGovernance(_futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGov {
        governance = futureGovernance;
        emit GovernanceAccepted(governance);
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        if (ILiquidityGauge(gauge).reward_data(_tokenReward).distributor == address(this)) {
            ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);

            emit RewardNotified(gauge, _tokenReward, _amount);
        }
    }

    /// @notice Distribute SDT to the gauge
    function _distributeSDT() internal {
        if (sdtDistributor != address(0)) {
            ISDTDistributor(sdtDistributor).distribute(gauge);
        }
    }

    /// @notice Charge fee for dao, liquidity, claimer
    function _chargeFee(address _token, uint256 _amount) internal returns(uint256 _charged) {
        if (daoFee != 0) {
            uint256 daoPart = _amount * daoFee / BASE_FEE;
            IERC20(_token).transfer(daoFeeRecipient, daoPart);
            _charged += daoPart;
        }
        if (liquidityFee != 0) {
            uint256 liquidityPart = _amount * liquidityFee / BASE_FEE;
            IERC20(_token).transfer(liquidityFeeRecipient, liquidityPart);
            _charged += liquidityPart;
        }
        if (claimerFee != 0) {
            uint256 claimerPart = _amount * liquidityFee / BASE_FEE;
            IERC20(_token).transfer(msg.sender, claimerPart);
            _charged += claimerPart;
        }

    }
}
