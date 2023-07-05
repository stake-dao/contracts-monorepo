// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "src/base/interfaces/ILocker.sol";
import "src/base/interfaces/ITokenMinter.sol";
import "src/base/interfaces/ILiquidityGauge.sol";

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MAVDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @dev Adapted for Maverick Voting Escrow.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract MAVDepositor {
    using SafeERC20 for IERC20;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Minimum lock duration.
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;

    /// @notice Maximum lock duration.
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    /// @notice Address of the token to be locked.
    address public immutable token;

    /// @notice Address of the locker contract.
    address public immutable locker;

    /// @notice Address of the sdToken minter contract.
    address public immutable minter;

    /// @notice Fee percent to users who spend gas to increase lock.
    uint256 public lockIncentivePercent = 10;

    /// @notice Incentive accrued in token to users who spend gas to increase lock.
    uint256 public incentiveToken = 0;

    /// @notice Gauge to deposit sdToken into.
    address public gauge;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Parameters to control lock duration.
    bool public relock = true;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when tokens are deposited.
    /// @param caller Address of the caller.
    /// @param user Address of the user.
    /// @param amount Amount of tokens deposited.
    /// @param lock Whether the tokens are locked.
    /// @param stake Whether the sdToken is staked in the gauge.
    event Deposited(address indexed caller, address indexed user, uint256 amount, bool lock, bool stake);

    /// @notice Event emitted when incentive tokens are received.
    /// @param caller Address of the caller.
    /// @param amount Amount of tokens received.
    event IncentiveReceived(address indexed caller, uint256 amount);

    /// @notice Event emitted when tokens are locked.
    /// @param user Address of the user.
    /// @param amount Amount of tokens locked.
    event TokenLocked(address indexed user, uint256 amount);

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Event emitted when the sdToken Operator is changed.
    event SdTokenOperatorChanged(address indexed newSdToken);

    /// @notice Event emitted Incentive percent is changed.
    event FeesChanged(uint256 newFee);

    /// @notice Throws if the deposit amount is zero.
    error AMOUNT_ZERO();

    /// @notice Throws if the address is zero.
    error ADDRESS_ZERO();

    constructor(address _token, address _locker, address _minter, address _gauge) {
        governance = msg.sender;

        token = _token;
        gauge = _gauge;
        minter = _minter;
        locker = _locker;
    }

    /// @notice Deposit tokens, and receive sdToken or sdTokenGauge in return.
    /// @param _amount Amount of tokens to deposit.
    /// @param _lock Whether to lock the tokens in the locker contract.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user to receive the sdToken.
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) public {
        if (_amount == 0) revert AMOUNT_ZERO();
        if (_user == address(0)) revert ADDRESS_ZERO();

        /// If _lock is true, lock tokens in the locker contract.
        if (_lock) {
            /// Transfer tokens to the locker contract and lock them.
            _amount += incentiveToken;
            IERC20(token).safeTransferFrom(msg.sender, locker, _amount);

            /// Lock the amount sent + incentiveToken.
            _lockToken(_amount);

            incentiveToken = 0;
        } else {
            /// Transfer tokens to this contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

            /// Compute call incentive and add to incentiveToken
            uint256 callIncentive = (_amount * lockIncentivePercent) / DENOMINATOR;

            /// Add call incentive to incentiveToken
            incentiveToken += callIncentive;

            /// Subtract call incentive from _amount
            _amount = _amount - callIncentive;
        }

        if (_stake && gauge != address(0)) {
            /// Mint sdToken to this contract.
            ITokenMinter(minter).mint(address(this), _amount);

            /// Approve sdToken to gauge.
            IERC20(minter).safeApprove(gauge, 0);
            IERC20(minter).safeApprove(gauge, _amount);

            /// Deposit sdToken into gauge for _user.
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            /// Mint sdToken to _user.
            ITokenMinter(minter).mint(_user, _amount);
        }
    }

    /// @notice Lock tokens held by the contract
    /// @dev The contract must have Token to lock
    function lockToken() external {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));

        if (tokenBalance > 0) {
            /// Transfer tokens to the locker contract and lock them.
            IERC20(token).safeTransfer(locker, tokenBalance);
            _lockToken(tokenBalance);
        }

        /// If there is incentive available give it to the user calling lockToken.
        if (incentiveToken > 0) {
            /// Mint incentiveToken to msg.sender.
            ITokenMinter(minter).mint(msg.sender, incentiveToken);

            /// Reset incentiveToken.
            incentiveToken = 0;
        }
    }

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal {
        // If there is Token available in the contract transfer it to the locker
        if (_amount > 0) {
            ILocker(locker).increaseLock(_amount, MIN_LOCK_DURATION);
            emit TokenLocked(msg.sender, _amount);
        }

        if (relock) {
            ILocker(locker).increaseLock(0, MAX_LOCK_DURATION);
        }
    }
}
