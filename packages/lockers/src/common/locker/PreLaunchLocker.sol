// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {PreLaunchBaseDepositor} from "src/common/depositor/PreLaunchBaseDepositor.sol";
import {IERC20} from "src/common/interfaces/IERC20.sol";
import {ILiquidityGaugeV4} from "src/common/interfaces/ILiquidityGaugeV4.sol";
import {IPreLaunchLocker} from "src/common/interfaces/IPreLaunchLocker.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";

/// @title PreLaunchLocker
/// @dev This contract implements a state machine with three states: IDLE, ACTIVE, and CANCELED
/**
 * @notice A contract that enables secure token locking before full protocol deployment. The PreLaunchLocker
 * serves as a solution for token locking during a protocol's pre-launch phase.
 * Unlike traditional lockers that require the complete protocol stack to be deployed, this contract allows users
 * to lock their tokens before the full protocol deployment.
 *
 * Key Features:
 * - Token Deposit: Users can deposit tokens which are securely held in the contract
 * - Pre-Launch Locking: Enables token locking mechanism before the full protocol deployment
 * - Immediate sdToken Minting: Mints sdTokens to users immediately upon deposit with 1:1 ratio
 * - Direct Gauge Integration: Optional direct staking of sdTokens into gauge upon deposit
 * - Safety Net: Includes a refund mechanism if the project launch is canceled
 *
 * State Machine:
 * - IDLE: Initial state where:
 *   • Users can deposit tokens via deposit() with optional immediate gauge staking
 *   • Governance can activate locker via lock(), transferring the initial tokens to depositor and moving state to ACTIVE
 *   • Governance can cancel locker via cancelLocker() and modify the state to CANCELED
 *   • Anyone can force cancel after delay via forceCancelLocker() and modify the state to CANCELED
 *
 * - ACTIVE: Activated state where:
 *   • No more deposits, withdrawals or cancellations possible
 *   • The user is now connected to the protocol via the depositor contract and the associated locker/gauge contracts
 *
 * - CANCELED: Terminal state where:
 *   • Supports withdrawal of both staked and unstaked sdTokens
 *   • No deposits or state changes possible
 *
 * @dev The contract uses a state machine pattern to manage the lifecycle of locked tokens:
 * 1. Users deposit tokens in IDLE state, receiving sdTokens immediately
 * 2. Governance can either:
 *    a) Activate the locker (IDLE -> ACTIVE) connecting it to the protocol via depositor
 *    b) Cancel the launch (IDLE -> CANCELED) enabling refunds of the initial tokens
 * 3. Both ACTIVE and CANCELED are terminal states
 */
/// @custom:contact contact@stakedao.org
contract PreLaunchLocker is IPreLaunchLocker {
    ///////////////////////////////////////////////////////////////
    /// --- STATE VARIABLES & CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The delay after which the locker can be force canceled by anyone.
    uint256 public immutable FORCE_CANCEL_DELAY;
    uint256 internal constant DEFAULT_FORCE_CANCEL_DELAY = 3 * 30 days;
    /// @notice The immutable token to lock.
    address public immutable token;
    /// @notice The sdToken address.
    ISdToken public immutable sdToken;
    /// @notice The gauge address.
    ILiquidityGaugeV4 public immutable gauge;

    /// @notice The current governance address.
    /// @custom:slot 0
    address public governance;
    /// @notice The timestamp of the locker creation.
    /// @custom:slot 0 (packed with `governance` <address>)
    uint96 public timestamp;
    /// @notice The depositor contract. Cannot be changed once set.
    /// @custom:slot 1
    PreLaunchBaseDepositor public depositor;

    enum STATE {
        IDLE,
        ACTIVE,
        CANCELED
    }

    /// @notice The state of the locker.
    /**
     * @dev The contract uses a state machine pattern to manage the lifecycle of locked tokens:
     * 1. Users deposit tokens in IDLE state
     * 2. Governance can either:
     *    a) Activate the locker (IDLE -> ACTIVE) connecting it to the protocol
     *    b) Cancel the launch (IDLE -> CANCELED) enabling refunds
     * 3. Both ACTIVE and CANCELED are terminal states
     *
     * Here's the State Machine Diagram:
     *
     *  +-------------------+
     *  |        IDLE       |
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
     * - IDLE -> ACTIVE: via `lock()`
     * - IDLE -> CANCELED: via `cancelLocker()`
     * - ACTIVE: terminal state
     * - CANCELED: terminal state
     */
    /// @custom:slot 1 (packed with `depositor`)
    STATE public state;

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

    /// @notice Event emitted each time a user stakes their sdTokens.
    /// @param caller The address who called the function.
    /// @param receiver The address who received the gauge token.
    /// @param gauge The gauge that the sdTokens were staked to.
    /// @param amount The amount of sdTokens staked.
    event TokensStaked(address indexed caller, address indexed receiver, address indexed gauge, uint256 amount);

    /// @notice Error thrown when a required parameter is set to the zero address.
    error REQUIRED_PARAM();
    /// @notice Error thrown when the caller is not the governance address.
    error ONLY_GOVERNANCE();
    /// @notice Error thrown when the token is not the expected one.
    error INVALID_TOKEN();
    /// @notice Error thrown when the gauge is not the expected one.
    error INVALID_GAUGE();
    /// @notice Error thrown when the sdToken is not the expected one.
    error INVALID_SD_TOKEN();
    /// @notice Error thrown when there is nothing to lock. This can happen if nobody deposited tokens before the locker was locked.
    ///         In that case, the locker is useless.
    error NOTHING_TO_LOCK();
    /// @notice Error thrown when the token is not transferred to the locker.
    error TOKEN_NOT_TRANSFERRED_TO_LOCKER();
    /// @notice Error thrown when the locker is not in the IDLE state when trying to deposit.
    error CANNOT_DEPOSIT_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is not in the IDLE state when trying to lock.
    error CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is not in the IDLE state when trying to cancel the launch.
    error CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is not CANCELED and the user tries to withdraw the initial token.
    error CANNOT_WITHDRAW_IDLE_OR_ACTIVE_LOCKER();
    /// @notice Error thrown when the locker is not in the IDLE state when trying to force cancel.
    error CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER();
    /// @notice Error thrown when the locker is not enough old to be force canceled.
    error CANNOT_FORCE_CANCEL_RECENTLY_CREATED_LOCKER();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS & CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Modifier to ensure the caller is the governance address.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert ONLY_GOVERNANCE();

        _;
    }

    /// @notice Sets the token to lock and the governance address.
    /// @param _token Address of the token to lock.
    /// @param _sdToken Address of the sdToken to mint.
    /// @param _gauge Address of the gauge to stake the sdTokens to.
    /// @param _customForceCancelDelay The optional custom force cancel delay. If set to 0, the default value will be used (3 months).
    /// @custom:reverts REQUIRED_PARAM if one of the given params is zero.
    /// @custom:reverts INVALID_SD_TOKEN if the given sdToken is not operated by this contract.
    /// @custom:reverts INVALID_GAUGE if the given gauge is not associated with the given sdToken.
    constructor(address _token, address _sdToken, address _gauge, uint256 _customForceCancelDelay) {
        if (_token == address(0) || _sdToken == address(0) || _gauge == address(0)) revert REQUIRED_PARAM();

        // ensure the given gauge contract is associated with the given sdToken
        if (ILiquidityGaugeV4(_gauge).staking_token() != _sdToken) revert INVALID_GAUGE();

        // set the immutable addresses
        token = _token;
        sdToken = ISdToken(_sdToken);
        gauge = ILiquidityGaugeV4(_gauge);

        // start the timer before the locker can be force canceled
        timestamp = uint96(block.timestamp);

        // set the custom force cancel delay if provided
        FORCE_CANCEL_DELAY = _customForceCancelDelay != 0 ? _customForceCancelDelay : DEFAULT_FORCE_CANCEL_DELAY;

        // set the state of the contract to idle and emit the state update event
        _setState(STATE.IDLE);

        // set the governance address and emit the event
        _setGovernance(msg.sender);
    }

    ////////////////////////////////////////////////////////////////
    /// --- DEPOSIT
    ///////////////////////////////////////////////////////////////

    /// @notice Deposit tokens for a given receiver.
    /// @param amount Amount of tokens to deposit.
    /// @param stake Whether to stake the tokens in the gauge.
    /// @param receiver The address to receive the sdToken or the gauge token.
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    /// @custom:reverts CANNOT_DEPOSIT_ACTIVE_OR_CANCELED_LOCKER if the locker is already associated with a depositor.
    function deposit(uint256 amount, bool stake, address receiver) public {
        if (amount == 0 || receiver == address(0)) revert REQUIRED_PARAM();

        // deposit aren't allowed once the locker leaves the idle state
        if (state != STATE.IDLE) revert CANNOT_DEPOSIT_ACTIVE_OR_CANCELED_LOCKER();

        // 1. transfer the tokens from the sender to the contract. Reverts if not enough tokens are approved.
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);

        ISdToken storedSdToken = sdToken;

        if (stake == true) {
            //  2.a. Either mint the sdTokens to this contract and stake them in the gauge for the caller
            ILiquidityGaugeV4 storedGauge = gauge;

            storedSdToken.mint(address(this), amount);
            storedSdToken.approve(address(storedGauge), amount);

            storedGauge.deposit(amount, receiver, false);

            emit TokensStaked(msg.sender, receiver, address(storedGauge), amount);
        } else {
            // 2.b. or mint the sdTokens directly to the caller (ratio 1:1 between token<>sdToken)
            sdToken.mint(receiver, amount);
        }
    }

    /// @notice Deposit tokens in this contract for the caller.
    /// @param amount Amount of tokens to deposit.
    /// @param stake Whether to stake the tokens in the gauge.
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    function deposit(uint256 amount, bool stake) external {
        deposit(amount, stake, msg.sender);
    }

    ////////////////////////////////////////////////////////////////
    /// --- LOCK
    ///////////////////////////////////////////////////////////////

    /// @notice Set the depositor and lock the tokens in the given depositor contract.
    /// @dev Can only be called once! This function sets the contract as active for ever.
    /// @param _depositor The address of the depositor.
    /// @custom:reverts ONLY_GOVERNANCE if the caller is not the governance address.
    /// @custom:reverts REQUIRED_PARAM if the given address is zero.
    /// @custom:reverts CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER if the contract is not in the idle state when trying to lock.
    /// @custom:reverts INVALID_TOKEN if the given address is not a valid depositor.
    /// @custom:reverts INVALID_GAUGE if the given address is not a valid gauge.
    /// @custom:reverts INVALID_SD_TOKEN if the given address is not a valid sdToken.
    /// @custom:reverts NOTHING_TO_LOCK if there is nothing to lock.
    /// @custom:reverts TOKEN_NOT_TRANSFERRED_TO_LOCKER if the locker contract doesn't hold the initial tokens.
    function lock(address _depositor) external onlyGovernance {
        // ensure the given address is not zero
        if (_depositor == address(0)) revert REQUIRED_PARAM();

        // ensure the locker is in the idle state
        if (state != STATE.IDLE) revert CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER();

        address storedToken = token;
        ISdToken storedSdToken = sdToken;

        // ensure the given depositor has the same token as the one stored in this contract
        if (PreLaunchBaseDepositor(_depositor).token() != storedToken) revert INVALID_TOKEN();

        // ensure the given depositor has the same gauge as the one stored in this contract
        if (PreLaunchBaseDepositor(_depositor).gauge() != address(gauge)) revert INVALID_GAUGE();

        // ensure the given depositor has the same sdToken as the one stored in this contract
        if (PreLaunchBaseDepositor(_depositor).minter() != address(storedSdToken)) revert INVALID_SD_TOKEN();

        // 1. set the given depositor
        depositor = PreLaunchBaseDepositor(_depositor);

        // 2. fetch the current balance of the contract to ensure there is something to lock
        uint256 balance = IERC20(storedToken).balanceOf(address(this));
        if (balance == 0) revert NOTHING_TO_LOCK();

        // 3. give the permission to the depositor to transfer the tokens held by this contract
        SafeTransferLib.safeApprove(storedToken, address(depositor), balance);

        // 4. Initiate a lock in the depositor contract with the balance of the contract
        //    This will lock the assets currently hold by this contract in the locker contract via the depositor
        //    The operation do not mint the sdTokens, as the sdToken have been minted over time to the account who deposited the tokens
        depositor.createLock(balance);

        // 5. ensure there is nothing left in the contract
        if (IERC20(token).balanceOf(address(this)) != 0) revert TOKEN_NOT_TRANSFERRED_TO_LOCKER();

        // 6. transfer the operator permission of the sdToken to the depositor contract
        sdToken.setOperator(address(depositor));

        // 7. set the state of the contract to active and emit the state update event
        _setState(STATE.ACTIVE);
    }

    ////////////////////////////////////////////////////////////////
    /// --- EMERGENCY METHODS
    ///////////////////////////////////////////////////////////////

    /// @notice Withdraw the previously deposited tokens if the launch has been canceled. This is an escape hatch for users.
    /// @dev This function can only be called if the locker is in the canceled state.
    /// @param amount Amount of tokens to withdraw.
    /**
     * @param staked Indicates if the sdTokens were staked in the gauge or not.
     *  • If true, the function will handle the withdrawal of sdTokens staked in the gauge
     *    before burning them. The caller must have approved this contract to transfer the gauge token.
     *  • If false, the function will simply burn the sdToken held by the caller.
     */
    /// @custom:reverts REQUIRED_PARAM if the given amount is zero.
    /// @custom:reverts CANNOT_WITHDRAW_IDLE_OR_ACTIVE_LOCKER if the locker is not in the canceled state.
    function withdraw(uint256 amount, bool staked) external {
        // ensure the amount is not zero
        if (amount == 0) revert REQUIRED_PARAM();

        // ensure the locker is in the canceled state
        if (state != STATE.CANCELED) revert CANNOT_WITHDRAW_IDLE_OR_ACTIVE_LOCKER();

        if (staked == true) {
            // transfer the gauge token held by the caller to this contract
            // will fail if the caller doesn't have enough balance in the gauge or forgot the approval
            gauge.transferFrom(msg.sender, address(this), amount);

            // use the gauge token transferred from the caller to this contract to withdraw the sdToken deposited in the gauge
            gauge.withdraw(amount, false);

            // burn the exact amount of sdToken previously held by the caller
            sdToken.burn(address(this), amount);
        } else {
            // burn the sdToken held by the caller. This will fail if caller's sdToken balance is insufficient
            sdToken.burn(msg.sender, amount);
        }

        // transfer back the default token to the caller
        SafeTransferLib.safeTransfer(token, msg.sender, amount);
    }

    /// @notice Set the state of the locker as CANCELED. It only happens if the launch of the campaign has been canceled.
    /// @custom:reverts ONLY_GOVERNANCE if the caller is not the stored governance address.
    /// @custom:reverts CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER if the locker is active.
    function cancelLocker() external onlyGovernance {
        if (state != STATE.IDLE) revert CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER();

        // 1. set the state of the contract to canceled and emit the state update event
        _setState(STATE.CANCELED);
    }

    /// @notice Force cancel the locker. Can only be called if the locker is in the idle state and the timestamp is older than the force cancel delay.
    ///         This function is an escape hatch allowing anyone to force cancel the locker if the governance is not responsive.
    ///         When the locker is in the canceled state, the users can withdraw their previously deposited tokens.
    /// @custom:reverts CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER if the locker is not in the idle state.
    /// @custom:reverts CANNOT_FORCE_CANCEL_RECENTLY_CREATED_LOCKER if the locker is not old enough to be force canceled.
    function forceCancelLocker() external {
        // check if the locker is in the idle state
        if (state != STATE.IDLE) revert CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER();

        // check if the timestamp is older than the force cancel delay
        if ((block.timestamp - timestamp) < FORCE_CANCEL_DELAY) {
            revert CANNOT_FORCE_CANCEL_RECENTLY_CREATED_LOCKER();
        }

        // force the state to CANCELED
        _setState(STATE.CANCELED);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    /// @custom:reverts ONLY_GOVERNANCE if the caller is not the stored governance address.
    function transferGovernance(address _governance) external onlyGovernance {
        _setGovernance(_governance);
    }

    /// @notice Internal function to update the governance address.
    /// @dev Never expose this internal function without gating the access with the onlyGovernance modifier, except the constructor
    /// @param _governance Address of the new governance.
    function _setGovernance(address _governance) internal {
        // emit the event with the current and the future governance addresses
        emit GovernanceUpdated(governance, _governance);

        governance = _governance;
    }

    ////////////////////////////////////////////////////////////////
    /// --- HELPERS METHODS
    ///////////////////////////////////////////////////////////////

    /// @notice Given the value of the state, return an user friendly label.
    /// @dev This function is a helper for frontend engineers or indexers to display the state of the locker in a user friendly way.
    /// @param _state The state of the locker as returned by the `state` variable or emitted in an event.
    /// @return label The user friendly label of the state. Return an empty string if the state is not recognized. Returned values are capitalized.
    function getUserFriendlyStateLabel(STATE _state) external pure returns (string memory label) {
        if (_state == STATE.IDLE) label = "IDLE";
        else if (_state == STATE.ACTIVE) label = "ACTIVE";
        else if (_state == STATE.CANCELED) label = "CANCELED";
    }

    /// @notice Internal function to update the state of the locker.
    /// @param _state The new state of the locker.
    function _setState(STATE _state) internal {
        state = _state;
        emit LockerStateUpdated(_state);
    }
}
