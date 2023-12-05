// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IVeToken} from "src/base/interfaces/IVeToken.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IFeeDistributor} from "src/base/interfaces/IFeeDistributor.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  VeCRVLocker
/// @notice Locker contract for locking tokens for a period of time compatible with the Voting Escrow contract from Curve
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
abstract contract VeCRVLocker {
    using SafeERC20 for IERC20;

    /// @notice Address of the depositor which will mint sdTokens.
    address public depositor;

    /// @notice Address of the accumulator which will accumulate rewards.
    address public accumulator;

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

    /// @notice Event emitted when the accumulator is changed.
    /// @param newAccumulator Address of the new accumulator.
    event AccumulatorChanged(address indexed newAccumulator);

    /// @notice Event emitted when a new governance is proposed.
    event GovernanceProposed(address indexed newGovernance);

    /// @notice Event emitted when the governance is changed.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Throws if caller is not the governance.
    error GOVERNANCE();

    /// @notice Throws if caller is not the governance or depositor.
    error GOVERNANCE_OR_DEPOSITOR();

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

    modifier onlyGovernanceOrAccumulator() {
        if (msg.sender != governance && msg.sender != accumulator) revert GOVERNANCE_OR_DEPOSITOR();
        _;
    }

    constructor(address _governance, address _token, address _veToken) {
        token = _token;
        veToken = _veToken;
        governance = _governance;
    }

    /// @dev Returns the name of the locker.
    function name() public pure virtual returns (string memory) {
        return "VeCRV Locker";
    }

    ////////////////////////////////////////////////////////////////
    /// --- LOCKER MANAGEMENT
    ///////////////////////////////////////////////////////////////

    /// @notice Create a lock for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function createLock(uint256 _value, uint256 _unlockTime) external virtual onlyGovernanceOrDepositor {
        IERC20(token).safeApprove(veToken, type(uint256).max);
        IVeToken(veToken).create_lock(_value, _unlockTime);

        emit LockCreated(_value, _unlockTime);
    }

    /// @notice Increase the lock amount or duration for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function increaseLock(uint256 _value, uint256 _unlockTime) external virtual onlyGovernanceOrDepositor {
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

    /// @notice Claim the rewards from the fee distributor.
    /// @param _feeDistributor Address of the fee distributor.
    /// @param _token Address of the token to claim.
    /// @param _recipient Address to send the tokens to.
    function claimRewards(address _feeDistributor, address _token, address _recipient)
        external
        virtual
        onlyGovernanceOrAccumulator
    {
        uint256 claimed = IFeeDistributor(_feeDistributor).claim();

        if (_recipient != address(0)) {
            IERC20(_token).safeTransfer(_recipient, claimed);
        }
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    /// @param _recipient Address to send the tokens to
    function release(address _recipient) external virtual onlyGovernance {
        IVeToken(veToken).withdraw();

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, _balance);
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

    function setAccumulator(address _accumulator) external onlyGovernance {
        emit AccumulatorChanged(accumulator = _accumulator);
    }

    /// @notice Execute an arbitrary transaction as the governance.
    /// @param to Address to send the transaction to.
    /// @param value Amount of ETH to send with the transaction.
    /// @param data Encoded data of the transaction.
    function execute(address to, uint256 value, bytes calldata data)
        external
        payable
        virtual
        onlyGovernance
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }

    receive() external payable {}
}
