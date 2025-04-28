// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Balancer} from "address-book/src/protocols/1.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {IVeToken} from "src/common/interfaces/IVeToken.sol";

/// @title Contract that accepts tokens and locks them
/// @author StakeDAO
contract BalancerDepositor is BaseDepositor, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Address of the veBAL token.
    address public constant VE_BAL = Balancer.VEBAL;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        BaseDepositor(_token, _locker, _minter, _gauge, 364 * 86_400)
        SafeModule(_gateway)
    {}

    ///////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Lock tokens held by the contract
    /// @dev The contract must have Token to lock
    function _lockToken(uint256 _amount) internal override {
        // Tell the locker to increase the amount of BAL locked in veBAL by `_amount`
        if (_amount != 0) _execute_increaseAmount(_amount);

        // Get current locker's locked balance in veBAL
        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

        // Check if the new unlock time is greater than the current locked balance's end time
        // The purpose of this division and multiplication by 1 weeks is to round down the timestamp to the nearest week.
        // This ensures that all locks end exactly on week boundaries rather than at arbitrary timestamps.
        bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVeToken(VE_BAL).locked__end(locker));

        // Increase the unlock time for the locker if possible
        if (_canIncrease) _execute_increaseUnlockTime(_unlockTime);
    }

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Increases the amount of BAL in the locker
    /// @param amount The amount of BAL to increase
    function _execute_increaseAmount(uint256 amount) internal virtual {
        _executeTransaction(VE_BAL, abi.encodeWithSelector(IVeToken.increase_amount.selector, amount));
    }

    /// @notice Increases the unlock time of the BAL in the locker
    /// @param unlockTime The new unlock time
    function _execute_increaseUnlockTime(uint256 unlockTime) internal virtual {
        _executeTransaction(VE_BAL, abi.encodeWithSelector(IVeToken.increase_unlock_time.selector, unlockTime));
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "4.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(BalancerDepositor).name;
    }
}
