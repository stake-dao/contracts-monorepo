// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "src/base/interfaces/ILocker.sol";
import "src/base/interfaces/ISdToken.sol";
import "src/base/interfaces/ITokenMinter.sol";
import "src/base/interfaces/ILiquidityGauge.sol";

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @dev Adapted for veCRV like Locker.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract Depositor {
    using SafeERC20 for IERC20;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Maximum lock duration.
    uint256 public immutable MAX_LOCK_DURATION;

    /// @notice Address of the token to be locked.
    address public immutable token;

    /// @notice Address of the locker contract.
    address public immutable locker;

    /// @notice Address of the sdToken minter contract.
    address public immutable minter;

    /// @notice Fee percent to users who spend gas to increase lock.
    uint256 public lockIncentivePercent = 10;

    /// @notice Incentive accrued in token to users who spend gas to increase lock.
    uint256 public incentiveToken;

    /// @notice Gauge to deposit sdToken into.
    address public gauge;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when a lock is created.
    /// @param amount Amount of tokens locked.
    /// @param duration Duration of the lock.
    event CreateLock(uint256 amount, uint256 duration);

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

    /// @notice Throws if caller is not the governance.
    error GOVERNANCE();

    /// @notice Throws if the deposit amount is zero.
    error AMOUNT_ZERO();

    /// @notice Throws if the address is zero.
    error ADDRESS_ZERO();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    constructor(address _token, address _locker, address _minter, address _gauge, uint256 _maxLockDuration) {
        governance = msg.sender;

        token = _token;
        gauge = _gauge;
        minter = _minter;
        locker = _locker;

        MAX_LOCK_DURATION = _maxLockDuration;

        /// Approve sdToken to gauge.
        IERC20(minter).safeApprove(gauge, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////////
    /// --- DEPOSIT & LOCK
    ///////////////////////////////////////////////////////////////

    /// @notice Initiate a lock in the Locker contract.
    /// @param _amount Amount of tokens to lock.
    function createLock(uint256 _amount) external virtual {
        /// Transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(locker), _amount);

        /// Can be called only once.
        ILocker(locker).createLock(_amount, block.timestamp + MAX_LOCK_DURATION);

        /// Mint sdToken to msg.sender.
        ITokenMinter(minter).mint(msg.sender, _amount);

        emit CreateLock(_amount, block.timestamp + MAX_LOCK_DURATION);
    }

    /// @notice Deposit tokens, and receive sdToken or sdTokenGauge in return.
    /// @param _amount Amount of tokens to deposit.
    /// @param _lock Whether to lock the tokens in the locker contract.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user to receive the sdToken.
    /// @dev If the lock is true, the tokens are directly sent to the locker and increase the lock amount as veToken.
    /// If the lock is false, the tokens are sent to this contract until someone locks them. A small percent of the deposit
    /// is used to incentivize users to lock the tokens.
    /// If the stake is true, the sdToken is staked in the gauge that distributes rewards. If the stake is false, the sdToken
    /// is sent to the user.
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) public {
        if (_amount == 0) revert AMOUNT_ZERO();
        if (_user == address(0)) revert ADDRESS_ZERO();

        /// If _lock is true, lock tokens in the locker contract.
        if (_lock) {
            /// Transfer tokens to this contract
            IERC20(token).safeTransferFrom(msg.sender, locker, _amount);

            /// Transfer the balance
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance != 0) {
                IERC20(token).safeTransfer(locker, balance);
            }

            /// Lock the amount sent + balance of the contract.
            _lockToken(balance + _amount);

            /// If an incentive is available, add it to the amount.
            if (incentiveToken != 0) {
                _amount += incentiveToken;

                emit IncentiveReceived(msg.sender, incentiveToken);

                incentiveToken = 0;
            }
        } else {
            /// Transfer tokens to the locker contract and lock them.
            IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

            /// Compute call incentive and add to incentiveToken
            uint256 callIncentive = (_amount * lockIncentivePercent) / DENOMINATOR;

            /// Subtract call incentive from _amount
            _amount -= callIncentive;

            /// Add call incentive to incentiveToken
            incentiveToken += callIncentive;
        }

        if (_stake) {
            /// Mint sdToken to this contract.
            ITokenMinter(minter).mint(address(this), _amount);

            /// Deposit sdToken into gauge for _user.
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            /// Mint sdToken to _user.
            ITokenMinter(minter).mint(_user, _amount);
        }
        emit Deposited(msg.sender, _user, _amount, _lock, _stake);
    }

    /// @notice Lock tokens held by the contract
    /// @dev The contract must have Token to lock
    function lockToken() external {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));

        if (tokenBalance != 0) {
            /// Transfer tokens to the locker contract and lock them.
            IERC20(token).safeTransfer(locker, tokenBalance);
            _lockToken(tokenBalance);
        }

        /// If there is incentive available give it to the user calling lockToken.
        if (incentiveToken != 0) {
            /// Mint incentiveToken to msg.sender.
            ITokenMinter(minter).mint(msg.sender, incentiveToken);

            emit IncentiveReceived(msg.sender, incentiveToken);

            /// Reset incentiveToken.
            incentiveToken = 0;
        }
    }

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal virtual {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the lock.
            ILocker(locker).increaseLock(_amount, block.timestamp + MAX_LOCK_DURATION);

            emit TokenLocked(msg.sender, _amount);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- GOVERNANCE PARAMETERS
    ///////////////////////////////////////////////////////////////

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }

    /// @notice Set the new operator for minting sdToken
    /// @param _minter operator minter address
    function setSdTokenMinterOperator(address _minter) external onlyGovernance {
        ISdToken(minter).setOperator(_minter);
        emit SdTokenOperatorChanged(_minter);
    }

    /// @notice Set the gauge to deposit sdToken
    /// @param _gauge gauge address
    function setGauge(address _gauge) external onlyGovernance {
        gauge = _gauge;

        /// Approve sdToken to gauge.
        IERC20(minter).safeApprove(gauge, type(uint256).max);
    }

    /// @notice Set the percentage of the lock incentive
    /// @param _lockIncentive Percentage of the lock incentive
    function setFees(uint256 _lockIncentive) external onlyGovernance {
        if (_lockIncentive >= 0 && _lockIncentive <= 30) {
            emit FeesChanged(lockIncentivePercent = _lockIncentive);
        }
    }
}
