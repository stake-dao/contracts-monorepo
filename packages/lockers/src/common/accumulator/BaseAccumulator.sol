// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {IFeeReceiver} from "herdaddy/interfaces/IFeeReceiver.sol";
import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {ISDTDistributor} from "src/common/interfaces/ISDTDistributor.sol";

/// @title BaseAccumulator
/// @notice Abstract contract used for any accumulator
/// @dev Interacting with the FeeReceiver (receiving and splitting fees)
/// @author StakeDAO
abstract contract BaseAccumulator {
    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 1e18;

    /// @notice Split struct
    /// @param receivers Array of receivers
    /// @param fees Array of fees
    /// @dev First go to the first receiver, then the second, and so on
    struct Split {
        address[] receivers;
        uint256[] fees; // Fee in basis points with 1e18 precision
    }

    /// @notice Fee split.
    Split private feeSplit;

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

    /// @notice Event emitted when the fee split is set
    event FeeSplitUpdated(Split newFeeSplit);

    /// @notice Event emitted when a new token reward is approved
    event RewardTokenApproved(address newRewardToken);

    /// @notice Event emitted when the claimer fee is set
    event ClaimerFeeUpdated(uint256 newClaimerFee);

    /// @notice Event emitted when the SDT distributor is set
    event SDTDistributorUpdated(address newSDTDistributor);

    /// @notice Event emitted when the fee receiver is set
    event FeeReceiverUpdated(address newFeeReceiver);

    /// @notice Event emitted when the strategy is set
    event StrategyUpdated(address newStrategy);

    /// @notice Event emitted when the governance update is proposed
    event GovernanceUpdateProposed(address newFutureGovernance);

    /// @notice Event emitted when the governance update is accepted
    event GovernanceUpdateAccepted(address newGovernance);

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
        if (_gauge == address(0) || _locker == address(0) || _governance == address(0) || _rewardToken == address(0)) {
            revert ZERO_ADDRESS();
        }

        gauge = _gauge;
        locker = _locker;
        rewardToken = _rewardToken;

        governance = _governance;

        claimerFee = 0.001e18; // 0.1%
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external virtual {}

    /// @notice Notify the whole acc balance of a token
    /// @param token token to notify
    /// @param notifySDT if notify SDT or not
    /// @param claimFeeStrategy if pull tokens from the fee receiver or not
    function notifyReward(address token, bool notifySDT, bool claimFeeStrategy) public virtual {
        uint256 amount = ERC20(token).balanceOf(address(this));
        // notify token as reward in sdToken gauge
        _notifyReward(token, amount, claimFeeStrategy);

        if (notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Notify the new reward to the LGV4
    /// @param tokenReward token to notify
    /// @param amount amount to notify
    /// @param claimFeeStrategy if pull tokens from the fee receiver or not (tokens already in that contract)
    function _notifyReward(address tokenReward, uint256 amount, bool claimFeeStrategy) internal virtual {
        _chargeFee(tokenReward, amount);

        if (claimFeeStrategy && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(tokenReward);
        }

        amount = ERC20(tokenReward).balanceOf(address(this));

        if (amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(tokenReward, amount);
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
        emit ClaimerFeeUpdated(claimerFee = _claimerFee);
    }

    /// @notice Set SDT distributor.
    /// @param _distributor SDT distributor address.
    function setDistributor(address _distributor) external onlyGovernance {
        emit SDTDistributorUpdated(sdtDistributor = _distributor);
    }

    /// @notice Set fee receiver (from Stategy)
    /// @param _feeReceiver Fee receiver address
    function setFeeReceiver(address _feeReceiver) external onlyGovernance {
        emit FeeReceiverUpdated(feeReceiver = _feeReceiver);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGovernance {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;

        emit GovernanceUpdateProposed(futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGovernance {
        governance = futureGovernance;

        futureGovernance = address(0);

        emit GovernanceUpdateAccepted(governance);
    }

    /// @notice Approve the distribution of a new token reward from the BaseAccumulator.
    /// @param _newTokenReward New token reward to be approved.
    function approveNewTokenReward(address _newTokenReward) external onlyGovernance {
        SafeTransferLib.safeApprove(_newTokenReward, gauge, type(uint256).max);

        emit RewardTokenApproved(_newTokenReward);
    }

    /// @notice Set fee split
    /// @param receivers array of receivers
    /// @param fees array of fees
    function setFeeSplit(address[] calldata receivers, uint256[] calldata fees) external onlyGovernance {
        if (receivers.length == 0 || receivers.length != fees.length) revert INVALID_SPLIT();

        uint256 totalFees;
        for (uint256 i = 0; i < fees.length; i++) {
            totalFees += fees[i];
        }
        if (totalFees > DENOMINATOR) revert FEE_TOO_HIGH();

        feeSplit = Split(receivers, fees);

        emit FeeSplitUpdated(feeSplit);
    }

    function setStrategy(address _strategy) external onlyGovernance {
        emit StrategyUpdated(strategy = _strategy);
    }

    /// @notice A function that rescue any ERC20 token
    /// @dev Can be called only by the governance
    /// @param _token token address
    /// @param _amount amount to rescue
    /// @param _recipient address to send token rescued
    function rescueERC20(address _token, uint256 _amount, address _recipient) external onlyGovernance {
        if (_recipient == address(0)) revert ZERO_ADDRESS();
        SafeTransferLib.safeTransfer(_token, _recipient, _amount);
    }

    function name() external view virtual returns (string memory) {
        return string("Base Accumulator");
    }

    /// @notice Get the version of the contract
    /// Version follows the Semantic Versioning (https://semver.org/)
    /// Major version is increased when backward compatibility is broken in this base contract.
    /// Minor version is increased when new features are added in this base contract.
    /// Patch version is increased when child contracts are updated.
    function version() external pure returns (string memory) {
        return "3.0.0";
    }

    receive() external payable {}
}
