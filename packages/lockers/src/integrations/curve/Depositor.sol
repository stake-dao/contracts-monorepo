// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {DepositorBase} from "src/DepositorBase.sol";
import {IVeToken} from "src/interfaces/IVeToken.sol";
import {SafeModule} from "src/utils/SafeModule.sol";

/// @title CurveDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CurveDepositor is DepositorBase, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Address of the veCRV token.
    address public constant VE_CRV = CurveProtocol.VECRV;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _token Address of the CRV token
    /// @param _locker Address of the sdCRV locker
    /// @param _minter Address of the sdCRV minter
    /// @param _gauge Address of the sdCRV gauge
    /// @param _gateway Address of the gateway
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        DepositorBase(_token, _locker, _minter, _gauge, 4 * 365 days)
        SafeModule(_gateway)
    {}

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        // Tell the locker to increase the amount of CRV locked in veCRV by `_amount`
        if (_amount != 0) _execute_increaseAmount(_amount);

        // Get current locker's locked balance in veCRV
        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

        // Check if the new unlock time is greater than the current locked balance's end time
        // The purpose of this division and multiplication by 1 weeks is to round down the timestamp to the nearest week.
        // This ensures that all locks end exactly on week boundaries rather than at arbitrary timestamps.
        bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVeToken(VE_CRV).locked__end(locker));

        // Increase the unlock time for the locker if possible
        if (_canIncrease) _execute_increaseUnlockTime(_unlockTime);
    }

    /// @notice Increases the unlock time of the locker for the CRV token
    /// @param unlockTime The new unlock time
    function _execute_increaseUnlockTime(uint256 unlockTime) internal virtual {
        _executeTransaction(VE_CRV, abi.encodeWithSelector(IVeToken.increase_unlock_time.selector, unlockTime));
    }

    /// @notice Increases the amount of CRV locked by the locker
    /// @param amount The amount of CRV to increase
    function _execute_increaseAmount(uint256 amount) internal virtual {
        _executeTransaction(VE_CRV, abi.encodeWithSelector(IVeToken.increase_amount.selector, amount));
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
        return type(CurveDepositor).name;
    }
}
