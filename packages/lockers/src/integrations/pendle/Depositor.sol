// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PendleProtocol} from "@address-book/src/PendleEthereum.sol";
import {DepositorBase} from "src/DepositorBase.sol";
import {IVePendle} from "src/interfaces/IVePendle.sol";
import {SafeModule} from "@shared/safe/SafeModule.sol";

/// @title Stake DAO Pendle Depositor
/// @notice Contract responsible for managing PENDLE token deposits, locking them in the Locker,
///         and minting sdPENDLE tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract PendleDepositor is DepositorBase, SafeModule {
    using SafeCast for uint256;

    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Address of the vePENDLE token.
    address public constant VE_PENDLE = PendleProtocol.VEPENDLE;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Initializes the Depositor contract with required dependencies
    /// @param _token Address of the PENDLE token
    /// @param _locker Address of the Stake DAO Pendle Locker contract
    /// @param _minter Address of the sdPENDLE minter contract
    /// @param _gauge Address of the sdPENDLE-gauge contract
    /// @param _gateway Address of the gateway contract
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        DepositorBase(_token, _locker, _minter, _gauge, 104 weeks)
        SafeModule(_gateway)
    {}

    /// Override the createLock function to prevent reverting.
    function createLock(uint256) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    /// @param amount The amount of PENDLE to lock
    function _lockToken(uint256 amount) internal virtual override {
        // Get the current expiry of the lock.
        (, uint128 expiry) = IVePendle(VE_PENDLE).positionData(locker);

        // Calculate the "new" possible unlock time.
        uint256 unlockTime = (block.timestamp + MAX_LOCK_DURATION) / 1 weeks * 1 weeks;

        // If the new unlock time is greater than the current locked balance's end time, use it.
        // Otherwise, use the current locked balance's end time (a valid unlock time is needed).
        uint256 _newUnlockTime = unlockTime > expiry ? unlockTime : expiry;

        // Tell the locker to increase the current position by `amount` and set the unlock time to `_newUnlockTime`.
        _execute_increaseLockPosition(amount, _newUnlockTime);
    }

    function _execute_increaseLockPosition(uint256 amount, uint256 unlockTime) internal virtual {
        _executeTransaction(
            VE_PENDLE,
            abi.encodeWithSelector(IVePendle.increaseLockPosition.selector, amount.toUint128(), unlockTime.toUint128())
        );
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "5.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(PendleDepositor).name;
    }
}
