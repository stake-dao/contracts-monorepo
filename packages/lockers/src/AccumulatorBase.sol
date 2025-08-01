// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @title AccumulatorBase
/// @notice Abstract contract used for any accumulator
/// @dev Interacting with the FeeReceiver (receiving and splitting fees)
/// @author StakeDAO
abstract contract AccumulatorBase {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 1e18;

    /// @notice sd gauge
    address public immutable gauge;

    /// @notice Main Reward Token distributed.
    address public immutable rewardToken;

    /// @notice sd locker
    address public immutable locker;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice Split struct
    /// @dev Each split occupies 1 slot of storage
    /// @param receiver Receiver address
    /// @param fee Fee in basis points with 1e18 precision
    struct Split {
        address receiver;
        uint96 fee;
    }

    /// @notice Fee split.
    /// @dev Receivers are processed in order of insertion
    Split[] private feeSplits;

    /// @notice Claimer Fee.
    uint256 public claimerFee;

    /// @notice Accountant address.
    address public accountant;

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice Fee receiver contracts defined in Strategy
    address public feeReceiver;

    ////////////////////////////////////////////////////////////////
    /// --- ERRORS
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

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when the fee split is set
    event FeeSplitUpdated(Split[] newFeeSplit);

    /// @notice Event emitted when a new token reward is approved
    event RewardTokenApproved(address newRewardToken);

    /// @notice Event emitted when the claimer fee is set
    event ClaimerFeeUpdated(uint256 newClaimerFee);

    /// @notice Event emitted when the fee receiver is set
    event FeeReceiverUpdated(address newFeeReceiver);

    /// @notice Event emitted when the accountant is set
    event AccountantUpdated(address newAccountant);

    /// @notice Event emitted when the governance update is proposed
    event GovernanceUpdateProposed(address newFutureGovernance);

    /// @notice Event emitted when the governance update is accepted
    event GovernanceUpdateAccepted(address newGovernance);

    /// @notice Event emitted when the fee is sent to the fee receiver
    event FeeTransferred(address indexed receiver, uint256 amount, bool indexed isClaimerFee);

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
    function claimAndNotifyAll() external virtual {}

    /// @notice Notify the whole accumulator balance of a token
    /// @param token token to notify
    function notifyReward(address token) public virtual {
        uint256 amount = ERC20(token).balanceOf(address(this));
        // notify the token to the liquidity gauge
        _notifyReward(token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Notify the new reward to the LGV4
    /// @param tokenReward token to notify
    /// @param amount amount to notify
    function _notifyReward(address tokenReward, uint256 amount) internal virtual {
        // Charge the fee for the DAO, liquidity and claimer
        _chargeFee(tokenReward, amount);

        // Split fees for the specified token using the fee receiver contract
        if (feeReceiver != address(0)) IFeeReceiver(feeReceiver).split(tokenReward);

        // Get the balance of the token in the accumulator and return if 0
        amount = ERC20(tokenReward).balanceOf(address(this));
        if (amount == 0) return;

        // Deposit the token to the gauge
        ILiquidityGauge(gauge).deposit_reward_token(tokenReward, amount);
    }

    /// @notice Charge fee for dao, liquidity, claimer
    /// @param _token token to charge fee for
    /// @param _amount amount to charge fee for
    function _chargeFee(address _token, uint256 _amount) internal virtual returns (uint256 _charged) {
        if (_amount == 0 || _token != rewardToken) return 0;

        // Send the fees to all the stored fee receivers based on their fee weight
        Split[] memory _feeSplit = getFeeSplit();

        uint256 _length = _feeSplit.length;
        uint256 fee;
        for (uint256 i; i < _length;) {
            fee = (_amount * _feeSplit[i].fee) / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, _feeSplit[i].receiver, fee);
            emit FeeTransferred(_feeSplit[i].receiver, fee, false);

            _charged += fee;

            unchecked {
                ++i;
            }
        }

        // If claimer fee is set, send the claimer fee to the caller
        uint256 _claimerFee = claimerFee;
        if (_claimerFee > 0) {
            fee = (_amount * _claimerFee) / DENOMINATOR;
            _charged += fee;

            SafeTransferLib.safeTransfer(_token, msg.sender, fee);
            emit FeeTransferred(msg.sender, fee, true);
        }
    }

    /// @notice Send the fees accumulated by the accountant to the fee receiver
    /// @dev `accountant` MUST be set by the child contract
    function _claimAccumulatedFee() internal virtual {
        IAccountant(accountant).claimProtocolFees();
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////

    function getFeeSplit() public view returns (Split[] memory) {
        return feeSplits;
    }

    function setClaimerFee(uint256 _claimerFee) external onlyGovernance {
        if (_claimerFee > DENOMINATOR) revert FEE_TOO_HIGH();
        emit ClaimerFeeUpdated(claimerFee = _claimerFee);
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

    /// @notice Approve the distribution of a new token reward from the AccumulatorBase.
    /// @param _newTokenReward New token reward to be approved.
    function approveNewTokenReward(address _newTokenReward) external onlyGovernance {
        SafeTransferLib.safeApprove(_newTokenReward, gauge, type(uint256).max);

        emit RewardTokenApproved(_newTokenReward);
    }

    /// @notice Set fee split
    /// @param splits array of splits
    function setFeeSplit(Split[] calldata splits) external onlyGovernance {
        if (splits.length == 0) revert INVALID_SPLIT();

        uint256 totalFees;
        for (uint256 i = 0; i < splits.length; i++) {
            totalFees += splits[i].fee;
        }
        if (totalFees > DENOMINATOR) revert FEE_TOO_HIGH();

        delete feeSplits;

        for (uint256 i = 0; i < splits.length; i++) {
            if (splits[i].receiver == address(0)) revert ZERO_ADDRESS();

            feeSplits.push(Split({receiver: splits[i].receiver, fee: uint96(splits[i].fee)}));
        }

        emit FeeSplitUpdated(splits);
    }

    function setAccountant(address _accountant) external onlyGovernance {
        if (_accountant == address(0)) revert ZERO_ADDRESS();
        emit AccountantUpdated(accountant = _accountant);
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
        return type(AccumulatorBase).name;
    }

    /// @notice Get the version of the contract
    /// Version follows the Semantic Versioning (https://semver.org/)
    /// Major version is increased when backward compatibility is broken in this base contract.
    /// Minor version is increased when new features are added in this base contract.
    /// Patch version is increased when child contracts are updated.
    function version() external pure virtual returns (string memory) {
        return "3.0.0";
    }

    receive() external payable {}
}
