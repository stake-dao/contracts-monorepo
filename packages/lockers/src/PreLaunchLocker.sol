// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {IERC20} from "src/common/interfaces/IERC20.sol";

/// @title PreLaunchLocker
/// @dev This contract implements a state machine with three states: DEFAULT, ACTIVE, and CANCELED
/**
 * @notice A contract that enables secure token locking before full protocol deployment. The PreLaunchLocker
 * serves as a solution for token locking during a protocol's pre-launch phase.
 * Unlike traditional lockers that require the complete protocol stack to be deployed, this contract allows users
 * to lock their tokens before the full protocol deployment.
 *
 * Key Features:
 * - Token Deposit: Users can deposit tokens which are securely held in the contract
 * - Pre-Launch Locking: Enables token locking mechanism before the full protocol deployment
 * - Token Wrapping: Upon protocol deployment, converts locked tokens to wrapped tokens (sdTokens)
 * - Flexible Redemption: Users can redeem sdTokens for staking or withdrawal
 * - Safety Net: Includes a refund mechanism if the project launch is canceled
 *
 * State Machine:
 * - DEFAULT: Initial state, accepts deposits
 * - ACTIVE: Activated after successful protocol deployment, converts tokens to sdTokens
 * - CANCELED: Enables refunds of tokens to all depositors if the project is canceled before being active
 *
 * @dev The contract uses a state machine pattern to manage the lifecycle of locked tokens:
 * 1. Users deposit tokens in DEFAULT state
 * 2. Governance can either:
 *    a) Activate the locker (DEFAULT -> ACTIVE) connecting it to the protocol
 *    b) Cancel the launch (DEFAULT -> CANCELED) enabling refunds
 * 3. Both ACTIVE and CANCELED are terminal states
 */
/// @custom:contact contact@stakedao.org
contract PreLaunchLocker {
    ///////////////////////////////////////////////////////////////
    /// --- STATE VARIABLES & CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The immutable token to lock.
    address public immutable token;

    /// @notice The current governance address.
    /// @custom:slot 0
    address public governance;
    /// @notice The sdToken address. Cannot be changed once set.
    /// @custom:slot 1
    address public sdToken;
    /// @notice The depositor contract. Cannot be changed once set.
    /// @custom:slot 2
    BaseDepositor public depositor;

    enum STATE {
        DEFAULT,
        ACTIVE,
        CANCELED
    }

    /// @notice The state of the locker.
    /**
     * @dev The contract uses a state machine pattern to manage the lifecycle of locked tokens:
     * 1. Users deposit tokens in DEFAULT state
     * 2. Governance can either:
     *    a) Activate the locker (DEFAULT -> ACTIVE) connecting it to the protocol
     *    b) Cancel the launch (DEFAULT -> CANCELED) enabling refunds
     * 3. Both ACTIVE and CANCELED are terminal states
     *
     * Here's the State Machine Diagram:
     *
     *  +-------------------+
     *  |      DEFAULT      |
     *  +-------------------+
     *       |           |
     *  lock |           | cancelLocker
     *       |           |
     *       ↓           ↓
     *  +---------+    +-----------+
     *  | ACTIVE  |    | CANCELED  |
     *  +---------+    +-----------+
     *
     * Transitions:
     * - DEFAULT -> ACTIVE: via `lock()`
     * - DEFAULT -> CANCELED: via `cancelLocker()`
     * - ACTIVE: terminal state
     * - CANCELED: terminal state
     */
    /// @custom:slot 2 (packed with `depositor`)
    STATE public state;

    /// @notice The deposits of the users. Track the number of tokens deposited by each user before the locker is associated with a depositor.
    /// @custom:slot 3 + n
    mapping(address account => uint256 amount) public balances;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted each time the governance address is updated.
    /// @param previousGovernanceAddress The previous governance address.
    /// @param newGovernanceAddress The new governance address.
    event GovernanceUpdated(address previousGovernanceAddress, address newGovernanceAddress);

    /// @notice Event emitted each time the state of the locker is updated.
    /// @param newState The new state of the locker.
    event LockerStateUpdated(STATE newState);

    /// @notice Error thrown when a required parameter is set to the zero address.
    error REQUIRED_PARAM();
    /// @notice Error thrown when the caller is not the governance address.
    error ONLY_GOVERNANCE();
    /// @notice Error thrown when the token stored in the given depositor doesn't match the locker's token.
    error INVALID_TOKEN();
    /// @notice Error thrown when there is nothing to lock. This can happen if nobody deposited tokens before the locker was locked. In that case, the locker is useless.
    error NOTHING_TO_LOCK();
    /// @notice Error thrown when deposits are not allowed anymore. This happens once a depositor contract is set.
    error DEPOSIT_NOT_ALLOWED_ANYMORE();
    /// @notice Error thrown when the sdToken is not minted.
    error SD_TOKEN_NOT_MINTED();
    /// @notice Error thrown when the user tries to withdraw more than the balance.
    error INSUFFICIENT_BALANCE();
    /// @notice Error thrown when the locker is not in the default state when trying to lock.
    error CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is active and the governance tries to cancel it.
    error CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is not CANCELED and the user tries to withdraw the initial token.
    error CANNOT_WITHDRAW_DEFAULT_LOCKER();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    /// @notice Modifier to ensure the caller is the governance address.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert ONLY_GOVERNANCE();

        _;
    }

    /// @notice Sets the token to lock and the governance address.
    /// @param _token Address of the token to lock.
    /// @custom:reverts REQUIRED_PARAM if the given address is zero.
    constructor(address _token) {
        if (_token == address(0)) revert REQUIRED_PARAM();

        // set the state of the contract to default and emit the state update event
        state = STATE.DEFAULT;
        emit LockerStateUpdated(STATE.DEFAULT);

        // set the token to lock
        token = _token;

        // set the governance to the caller
        _setGovernance(msg.sender);
    }

    ////////////////////////////////////////////////////////////////
    /// --- DEPOSIT & WITHDRAW
    ///////////////////////////////////////////////////////////////

    /// @notice Deposit tokens in this contract.
    /// @param amount Amount of tokens to deposit.
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    /// @custom:reverts DEPOSIT_NOT_ALLOWED_ANYMORE if the locker is already associated with a depositor.
    function deposit(uint256 amount) public {
        if (amount == 0) revert REQUIRED_PARAM();

        // deposit aren't allowed anymore if the tokens have been locked
        if (state == STATE.ACTIVE) revert DEPOSIT_NOT_ALLOWED_ANYMORE();

        // 1. transfer the tokens from the sender to the contract. Reverts if not enough tokens are approved.
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);

        // 2. increase the balance of the sender by the amount deposited
        balances[msg.sender] += amount;
    }

    /// @notice Withdraw the given amount of tokens. The relation between the token and the sdToken is 1:1.
    /// @dev If the locker is active, withdraw the sdTokens held by the caller.
    ///      If the locker is not active, withdraw the initial token only if the locker is CANCELED.
    /// @param amount Amount of tokens to withdraw.
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    /// @custom:reverts INSUFFICIENT_BALANCE if the user has insufficient balance.
    /// @custom:reverts CANNOT_WITHDRAW_DEFAULT_LOCKER if the locker is not CANCELED and the user tries to withdraw the initial token.
    function withdraw(uint256 amount) public {
        // ensure the amount is not zero
        if (amount == 0) revert REQUIRED_PARAM();

        // check if the user has enough balance
        if (balances[msg.sender] < amount) revert INSUFFICIENT_BALANCE();

        // 1. decrease the balance of the sender by the amount withdrawn
        balances[msg.sender] -= amount;

        if (state == STATE.ACTIVE) {
            // 2.a withdraw the sdTokens held by the caller
            SafeTransferLib.safeTransfer(sdToken, msg.sender, amount);
        } else if (state == STATE.CANCELED) {
            // 2.b withdraw the initial token only if the locker is CANCELED
            SafeTransferLib.safeTransfer(token, msg.sender, amount);
        } else {
            // (i.e. state == STATE.DEFAULT)
            revert CANNOT_WITHDRAW_DEFAULT_LOCKER();
        }
    }

    /// @notice Withdraw all the tokens held by the caller.
    /// @dev If the locker is active, withdraw all the sdTokens held by the caller.
    ///      If the locker is not active, withdraw all the initial tokens only if the locker is CANCELED.
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    /// @custom:reverts INSUFFICIENT_BALANCE if the user has insufficient balance.
    /// @custom:reverts CANNOT_WITHDRAW_DEFAULT_LOCKER if the locker is not CANCELED and the user tries to withdraw the initial token.
    function withdraw() external {
        withdraw(balances[msg.sender]);
    }

    ////////////////////////////////////////////////////////////////
    /// --- ADMIN METHODS
    ///////////////////////////////////////////////////////////////

    /// @notice Lock the tokens in the given depositor contract.
    /// @param _depositor The address of the depositor.
    /// @dev Can only be called once (!)
    /// @custom:reverts CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER if the contract is not in the default state when trying to lock.
    /// @custom:reverts REQUIRED_PARAM if the given address is zero.
    /// @custom:reverts INVALID_TOKEN if the given address is not a valid depositor.
    /// @custom:reverts NOTHING_TO_LOCK if there is nothing to lock.
    function lock(address _depositor) external onlyGovernance {
        // ensure the given address is not zero
        if (_depositor == address(0)) revert REQUIRED_PARAM();

        // ensure the given depositor has the same token as the locker
        if (BaseDepositor(_depositor).token() != token) revert INVALID_TOKEN();

        // ensure the locker is in the default state
        if (state != STATE.DEFAULT) revert CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER();

        // 1. set the depositor and the address of the associated sdToken
        depositor = BaseDepositor(_depositor);
        sdToken = depositor.minter();

        // 2. fetch the current balance of the contract to ensure there is anything to lock
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NOTHING_TO_LOCK();

        // 3. give the permission to the depositor to transfer the tokens held by this contract
        SafeTransferLib.safeApprove(token, address(depositor), balance);

        // 4. Initiate a lock in the depositor contract with the balance of the contract
        //    This will lock the assets currently hold by this contract in the depositor contract
        //    AND mint the associated sdToken in favor of this contract
        depositor.createLock(balance);

        // 5. ensure we received the minted sdToken. There is a 1:1 relationship between the amount of tokens locked and the amount of sdTokens minted.
        if (IERC20(sdToken).balanceOf(address(this)) != balance) revert SD_TOKEN_NOT_MINTED();

        // 6. set the state of the contract to active and emit the state update event
        state = STATE.ACTIVE;
        emit LockerStateUpdated(STATE.ACTIVE);
    }

    /// @notice Set the state of the locker as CANCELED. It only happens if the launch of the campaign has been canceled.
    /// @custom:reverts ONLY_GOVERNANCE if the caller is not the stored governance address.
    /// @custom:reverts CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER if the locker is active.
    function cancelLocker() external onlyGovernance {
        if (state != STATE.DEFAULT) revert CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER();

        // 1. set the state of the contract to canceled and emit the state update event
        state = STATE.CANCELED;
        emit LockerStateUpdated(STATE.CANCELED);
    }

    /// @notice Internal function to update the governance address.
    /// @dev Never expose this internal function without gating the access with the onlyGovernance modifier, except the constructor
    /// @param _governance Address of the new governance.
    function _setGovernance(address _governance) internal {
        // emit the event with the current and the future governance addresses
        emit GovernanceUpdated(governance, _governance);

        governance = _governance;
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    /// @custom:reverts ONLY_GOVERNANCE if the caller is not the stored governance address.
    function transferGovernance(address _governance) external onlyGovernance {
        _setGovernance(_governance);
    }

    /// @notice Given the value of the state, return an user friendly label.
    /// @dev This function is a helper for frontend engineers or indexers to display the state of the locker in a user friendly way.
    /// @param _state The state of the locker as returned by the `state` variable or emitted in an event.
    /// @return label The user friendly label of the state. Return an empty string if the state is not recognized. Returned values are capitalized.
    function getUserFriendlyStateLabel(STATE _state) external pure returns (string memory label) {
        if (_state == STATE.DEFAULT) label = "DEFAULT";
        else if (_state == STATE.ACTIVE) label = "ACTIVE";
        else if (_state == STATE.CANCELED) label = "CANCELED";
    }
}
