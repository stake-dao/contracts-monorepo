// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {IVeToken} from "src/base/interfaces/IVeToken.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  FXNLocker
/// @notice Locker contract for locking tokens for a period of time
/// @dev Adapted for Maverick Voting Escrow.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract FXNLocker {
    using SafeERC20 for IERC20;

    /// @notice Address of the depositor which will mint sdTokens.
    address public depositor;

    /// @notice Address of the governance contract.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Address of the token being locked.
    address public immutable token;

    /// @notice Address of the Voting Escrow contract.
    address public immutable veToken;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when tokens are released from the locker.
    /// @param user Address who released the tokens.
    /// @param value Amount of tokens released.
    event Released(address indexed user, uint256 value);

    /// @notice Event emitted when a lock is created.
    /// @param value Amount of tokens locked.
    /// @param duration Duration of the lock.
    event LockCreated(uint256 value, uint256 duration);

    /// @notice Event emitted when a lock is increased.
    /// @param value Amount of tokens locked.
    /// @param duration Duration of the lock.
    event LockIncreased(uint256 value, uint256 duration);

    /// @notice Event emitted when the depositor is changed.
    /// @param newDepositor Address of the new depositor.
    event DepositorChanged(address indexed newDepositor);

    /// @notice Event emitted when a new governance is proposed.
    event GovernanceProposed(address indexed newGovernance);

    /// @notice Event emitted when the governance is changed.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Throws if caller is not the governance.
    error GOVERNANCE();

    /// @notice Throws if caller is not the governance or depositor.
    error GOVERNANCE_OR_DEPOSITOR();

    /// @notice Throws if a lock already exists for the contract.
    error LOCK_ALREADY_EXISTS();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    modifier onlyGovernanceOrDepositor() {
        if (msg.sender != governance && msg.sender != depositor) revert GOVERNANCE_OR_DEPOSITOR();
        _;
    }

    constructor(address _governance, address _token, address _veToken) {
        token = _token;
        veToken = _veToken;
        governance = _governance;
    }

    function name() external pure returns (string memory) {
        return "FXN Locker";
    }

    ////////////////////////////////////////////////////////////////
    /// --- LOCKER MANAGEMENT
    ///////////////////////////////////////////////////////////////

    /// @notice Create a lock for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function createLock(uint256 _value, uint256 _unlockTime) external onlyGovernance {
        IERC20(token).safeApprove(veToken, type(uint256).max);
        IVeToken(veToken).create_lock(_value, _unlockTime);

        emit LockCreated(_value, _unlockTime);
    }

    /// @notice Increase the lock amount or duration for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function increaseLock(uint256 _value, uint256 _unlockTime) external onlyGovernanceOrDepositor {
        if (_value > 0) {
            IVeToken(veToken).increase_amount(_value);
        }

        if (_unlockTime > 0) {
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVeToken(veToken).locked__end(address(this)));

            if (_canIncrease) {
                IVeToken(veToken).increase_unlock_time(_unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    /// @param _recipient Address to send the tokens to
    function release(address _recipient) external onlyGovernance {
        IVeToken(veToken).withdraw();

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    ////////////////////////////////////////////////////////////////
    /// --- GOVERNANCE PARAMETERS
    ///////////////////////////////////////////////////////////////

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        emit GovernanceProposed(futureGovernance = _governance);
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();
        emit GovernanceChanged(governance = msg.sender);
    }

    /// @notice Change the depositor address.
    /// @param _depositor Address of the new depositor.
    function setDepositor(address _depositor) external onlyGovernance {
        emit DepositorChanged(depositor = _depositor);
    }

    /// @notice Execute an arbitrary transaction as the governance.
    /// @param to Address to send the transaction to.
    /// @param value Amount of ETH to send with the transaction.
    /// @param data Encoded data of the transaction.
    function execute(address to, uint256 value, bytes calldata data)
        external
        payable
        onlyGovernance
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    receive() external payable {}
}
