// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolContext} from "src/interfaces/IProtocolContext.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title ProtocolContext
/// @author Stake DAO
/// @notice Base contract that handles common protocol-related logic for Strategy and Harvester
/// @dev Provides shared functionality for handling GATEWAY and LOCKER relationships
contract ProtocolContext is IProtocolContext {
    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The protocol identifier
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The locker contract address
    address public immutable LOCKER;

    /// @notice The gateway contract address
    address public immutable GATEWAY;

    /// @notice The accountant contract address
    address public immutable ACCOUNTANT;

    /// @notice The reward token address
    address public immutable REWARD_TOKEN;

    /// @notice The protocol controller contract
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when a required address is zero
    error ZeroAddress();

    /// @notice Error thrown when a protocol ID is zero
    error InvalidProtocolId();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the base contract with protocol ID, controller, locker, and gateway
    /// @param _protocolId The protocol identifier
    /// @param _protocolController The protocol controller contract address
    /// @param _locker The locker contract address (can be zero, in which case GATEWAY is used)
    /// @param _gateway The gateway contract address
    /// @custom:throws ZeroAddress If the protocol controller or gateway address is zero
    constructor(bytes4 _protocolId, address _protocolController, address _locker, address _gateway) {
        require(_protocolController != address(0) && _gateway != address(0), ZeroAddress());
        require(_protocolId != bytes4(0), InvalidProtocolId());

        GATEWAY = _gateway;
        PROTOCOL_ID = _protocolId;
        ACCOUNTANT = IProtocolController(_protocolController).accountant(_protocolId);
        REWARD_TOKEN = IAccountant(ACCOUNTANT).REWARD_TOKEN();
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);

        // In some cases (L2s), the locker is the same as the gateway.
        if (_locker == address(0)) {
            LOCKER = GATEWAY;
        } else {
            LOCKER = _locker;
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Executes a transaction through the gateway/module manager
    /// @dev Handles the common pattern of executing transactions through the gateway/module manager
    ///      based on whether LOCKER is the same as GATEWAY
    /// @param target The address of the contract to interact with
    /// @param data The calldata to send to the target
    function _executeTransaction(address target, bytes memory data) internal returns (bool success) {
        if (LOCKER == GATEWAY) {
            // If locker is the gateway, execute directly on the target
            success = IModuleManager(GATEWAY).execTransactionFromModule(target, 0, data, IModuleManager.Operation.Call);
        } else {
            // Otherwise execute through the locker's execute function
            success = IModuleManager(GATEWAY).execTransactionFromModule(
                LOCKER,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                IModuleManager.Operation.Call
            );
        }
    }
}
