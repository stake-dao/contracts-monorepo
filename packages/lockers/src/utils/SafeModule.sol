// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Enum} from "@safe/contracts/Safe.sol";
import {ISafe} from "src/interfaces/ISafeLocker.sol";

/// @title Stake DAO Safe Module
/// @notice Defining logic to call execute as a Safe module on the locker
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////
    error ExecFromSafeModuleFailed();

    /// @notice Error thrown when the provided gateway is a zero address
    error InvalidGateway();

    ///////////////////////////////////////////////////////////////
    /// --- CONSTANT
    ///////////////////////////////////////////////////////////////

    /// @notice The gateway contract address
    address public immutable GATEWAY;

    /// @notice Constructor for the SafeModule contract
    /// @dev The address of the gateway can be the same as the locker.
    ///      In that case, the execution is done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the locker to call the target contracts.
    /// @param _gateway The address of the gateway contract.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gateway) {
        if (_gateway == address(0)) revert InvalidGateway();
        GATEWAY = _gateway;
    }

    ///////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Executes a transaction through the Safe module system
    /// @dev Handle execution through either the gateway directly or through a locker's execute function
    /// @param _target The contract address to execute the transaction on
    /// @param _data The calldata to execute on the target contract
    /// @return returnData The data returned from the executed transaction
    /// @custom:throws ExecFromSafeModuleFailed if the Safe module execution fails
    function _executeTransaction(address _target, bytes memory _data) internal returns (bytes memory returnData) {
        address locker = _getLocker();
        bool success;

        // If the `gateway` is the locker, tell the `gateway` to directly call `target`
        if (locker == GATEWAY) {
            (success, returnData) =
                ISafe(locker).execTransactionFromModuleReturnData(_target, 0, _data, Enum.Operation.Call);
        } else {
            // Otherwise, the `gateway` pass the execution to the `locker` to call `target`
            (success, returnData) = ISafe(GATEWAY).execTransactionFromModuleReturnData(
                locker,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", _target, 0, _data),
                Enum.Operation.Call
            );
        }

        if (!success) revert ExecFromSafeModuleFailed();
        return returnData;
    }

    ///////////////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _getLocker() internal view virtual returns (address);
}
