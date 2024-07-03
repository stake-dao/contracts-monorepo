// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {IFeeReceiver} from "herdaddy/interfaces/IFeeReceiver.sol";
import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

/// @title Accumulator V2
/// @notice Abstract contract used for any accumulator
/// @dev Interacting with the FeeReceiver (receiving and splitting fees)
/// @author StakeDAO
abstract contract AccumulatorV2 {
    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Split struct
    /// @param receivers Array of receivers
    /// @param fees Array of fees
    /// @dev First go to the first receiver, then the second, and so on
    /// @dev Fee in basis points, where 10,000 basis points = 100%
    struct Split {
        address[] receivers;
        uint256[] fees; // Fee in basis points, where 10,000 basis points = 100%
    }

    /// @notice Fee split.
    Split feeSplit;

    /// @notice SDT distributor
    address public sdtDistributor;

    /// @notice Claimer Fee.
    uint256 public claimerFee;

    /// @notice sd gauge
    address public immutable gauge;

    /// @notice Main Reward Token distributed.
    address public immutable rewardToken;

    /// @notice sd locker
    address public immutable locker;

    /// @notice Strategy address.
    address public strategy;

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice Fee receiver contracts defined in Strategy
    address public feeReceiver;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when the claimer fee is set
    event ClaimerFeeSet(uint256 claimerFee);

    /// @notice Emitted when the fee receiver is set
    event FeeReceiverSet(address _feeReceiver);

    /// @notice Event emitted when an ERC20 token is rescued
    event ERC20Rescued(address token, uint256 amount);

    /// @notice Event emitted when a new future governance has set
    event TransferGovernance(address futureGovernance);

    /// @notice Event emitted when the future governance accepts to be the governance
    event GovernanceChanged(address governance);

    /// @notice Error emitted when an onlyGovernance function has called by a different address
    error GOVERNANCE();

    /// @notice Error emitted when the total fee would be more than 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when an onlyFutureGovernance function has called by a different address
    error FUTURE_GOVERNANCE();

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    /// @notice Error emitted when the fee is invalid
    error INVALID_SPLIT();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    /// @notice Modifier to check if the caller is the future governance
    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert FUTURE_GOVERNANCE();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _rewardToken, address _locker, address _governance) {
        gauge = _gauge;
        locker = _locker;
        rewardToken = _rewardToken;

        governance = _governance;

        claimerFee = 10; // 0.1%
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy) external virtual {}

    /// @notice Claims a reward token for the locker and notify them to the LGV4
    function claimTokenAndNotifyAll(address token, bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy)
        external
        virtual
    {}

    /// @notice Notify the whole acc balance of a token
    /// @param _token token to notify
    /// @param _notifySDT if notify SDT or not
    /// @param _pullFromFeeReceiver if pull tokens from the fee receiver or not
    function notifyReward(address _token, bool _notifySDT, bool _pullFromFeeReceiver) public virtual {
        uint256 amount = ERC20(_token).balanceOf(address(this));
        // notify token as reward in sdToken gauge
        _notifyReward(_token, amount, _pullFromFeeReceiver);

        if (_notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    /// @param _pullFromFeeReceiver if pull tokens from the fee receiver or not (tokens already in that contract)
    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal virtual {
        _chargeFee(_tokenReward, _amount);

        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    /// @notice Distribute SDT to the gauge
    function _distributeSDT() internal {
        if (sdtDistributor != address(0)) {
            ISDTDistributor(sdtDistributor).distribute(gauge);
        }
    }

    /// @notice Charge fee for dao, liquidity, claimer
    /// @param _token token to charge fee for
    /// @param _amount amount to charge fee for
    function _chargeFee(address _token, uint256 _amount) internal virtual returns (uint256 _charged) {
        if (_amount == 0 || _token != rewardToken) return 0;

        Split memory _feeSplit = getFeeSplit();
        uint256 fee;
        for (uint256 i = 0; i < _feeSplit.receivers.length; i++) {
            fee = (_amount * _feeSplit.fees[i]) / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, _feeSplit.receivers[i], fee);

            _charged += fee;
        }

        /// Claimer fee.
        fee = (_amount * claimerFee) / DENOMINATOR;
        SafeTransferLib.safeTransfer(_token, msg.sender, fee);

        _charged += fee;
    }

    /// @notice Take the fees accumulated from the strategy and sending to the fee receiver
    /// @dev Need to be done before calling `split`, but claimProtocolFees is permissionless.
    /// @dev Strategy not set in that abstract contract, must be implemented by child contracts
    function _claimFeeStrategy() internal virtual {
        IStrategy(strategy).claimProtocolFees();
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////

    function getFeeSplit() public view returns (Split memory) {
        return feeSplit;
    }

    function setClaimerFee(uint256 _claimerFee) external onlyGovernance {
        if (_claimerFee > DENOMINATOR) revert FEE_TOO_HIGH();
        emit ClaimerFeeSet(claimerFee = _claimerFee);
    }

    /// @notice Set SDT distributor.
    /// @param _distributor SDT distributor address.
    function setDistributor(address _distributor) external onlyGovernance {
        sdtDistributor = _distributor;
    }

    /// @notice Set fee receiver (from Stategy)
    /// @param _feeReceiver Fee receiver address
    function setFeeReceiver(address _feeReceiver) external onlyGovernance {
        emit FeeReceiverSet(feeReceiver = _feeReceiver);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGovernance {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
        emit TransferGovernance(_futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGovernance {
        governance = futureGovernance;
        emit GovernanceChanged(governance);
    }

    /// @notice Approve the distribution of a new token reward from the Accumulator.
    /// @param _newTokenReward New token reward to be approved.
    function approveNewTokenReward(address _newTokenReward) external onlyGovernance {
        SafeTransferLib.safeApprove(_newTokenReward, gauge, type(uint256).max);
    }

    /// @notice Set fee split
    /// @param receivers array of receivers
    /// @param fees array of fees
    function setFeeSplit(address[] calldata receivers, uint256[] calldata fees) external onlyGovernance {
        if (receivers.length == 0 || receivers.length != fees.length) revert INVALID_SPLIT();
        feeSplit = Split(receivers, fees);
    }

    function setStrategy(address _strategy) external onlyGovernance {
        strategy = _strategy;
    }

    /// @notice A function that rescue any ERC20 token
    /// @dev Can be called only by the governance
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external onlyGovernance {
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        SafeTransferLib.safeTransfer(_token, _recipient, _amount);
        emit ERC20Rescued(_token, _amount);
    }

    receive() external payable {}
}
