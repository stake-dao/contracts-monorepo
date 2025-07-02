// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {YearnProtocol} from "@address-book/src/YearnEthereum.sol";
import {DepositorBase} from "src/DepositorBase.sol";
import {IVeYFI} from "src/interfaces/IVeYFI.sol";
import {SafeModule} from "src/utils/SafeModule.sol";

/// @title Stake DAO Yearn Depositor
/// @notice Contract responsible for managing YFI token deposits, locking them in the Locker,
///         and minting sdYFI tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract YearnDepositor is DepositorBase, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Address of the veYFI token.
    address public constant VE_YFI = YearnProtocol.VEYFI;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Initializes the Depositor contract with required dependencies
    /// @param _token Address of the YFI token
    /// @param _locker Address of the Stake DAO Yearn Locker contract
    /// @param _minter Address of the sdYFI minter contract
    /// @param _gauge Address of the sdYFI-gauge contract
    /// @param _gateway Address of the gateway contract
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        DepositorBase(_token, _locker, _minter, _gauge, 4 * 370 days)
        SafeModule(_gateway)
    {}

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        // Get current locker's locked balance in veYFI
        IVeYFI.LockedBalance memory _lockedBalance = IVeYFI(VE_YFI).locked(locker);

        /// In the case of Yearn, we can lock up to 10 years.
        /// But 4 years plus a couple months is enough to avoid decay.
        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

        // Calculate the new unlock time.
        // If the new unlock time is greater than the current locked balance's end time, use the new unlock time.
        // Otherwise, use 0 as the unlock time.
        uint256 _newUnlockTime = (_unlockTime / 1 weeks * 1 weeks) > _lockedBalance.end ? _unlockTime : 0;

        // If it's needed, modify the lock of the locker
        if (_amount != 0 || _newUnlockTime != 0) _execute_modifyLock(_amount, _newUnlockTime);
    }

    /// @notice Modifies the lock of the locker
    /// @dev Compare to the ve contract depositors, Yearn allow us to increase the amount AND the unlock time at the same time.
    /// @param amount The amount of YFI to modify Can be 0.
    /// @param unlockTime The new unlock time. Can be 0.
    function _execute_modifyLock(uint256 amount, uint256 unlockTime) internal virtual {
        _executeTransaction(VE_YFI, abi.encodeWithSelector(IVeYFI.modify_lock.selector, amount, unlockTime));
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "2.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(YearnDepositor).name;
    }
}
