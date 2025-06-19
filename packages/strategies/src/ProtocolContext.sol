// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";

import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title ProtocolContext
/// @author Stake DAO
/// @notice Base contract providing shared protocol configuration and transaction execution
/// @dev Inherited by Strategy and other protocol-specific contracts to ensure consistent configuration
contract ProtocolContext {
    //////////////////////////////////////////////////////
    // --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Unique identifier for the protocol (e.g., keccak256("CURVE") for Curve)
    /// @dev Used to look up protocol-specific components in ProtocolController
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The locker contract that holds and manages protocol tokens (e.g., veCRV)
    /// @dev On L2s, this may be the same as GATEWAY when no separate locker exists
    address public immutable LOCKER;

    /// @notice Safe multisig that owns the locker and executes privileged operations
    /// @dev All protocol interactions go through this gateway for security
    address public immutable GATEWAY;

    /// @notice The accountant responsible for tracking rewards and user balances
    /// @dev Retrieved from ProtocolController during construction
    address public immutable ACCOUNTANT;

    /// @notice The main reward token for this protocol (e.g., CRV for Curve)
    /// @dev Retrieved from the accountant's configuration
    address public immutable REWARD_TOKEN;

    /// @notice Reference to the central registry for protocol components
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when a required address is zero
    error ZeroAddress();

    /// @notice Error thrown when a protocol ID is zero
    error InvalidProtocolId();

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes protocol configuration that all inheriting contracts will use
    /// @dev Retrieves accountant and reward token from ProtocolController for consistency
    /// @param _protocolId The protocol identifier (must match registered protocol in controller)
    /// @param _protocolController The protocol controller contract address
    /// @param _locker The locker contract address (pass address(0) for L2s where gateway acts as locker)
    /// @param _gateway The gateway contract address (Safe multisig)
    /// @custom:throws ZeroAddress If protocol controller or gateway is zero
    /// @custom:throws InvalidProtocolId If protocol ID is empty
    constructor(bytes4 _protocolId, address _protocolController, address _locker, address _gateway) {
        require(_protocolController != address(0) && _gateway != address(0), ZeroAddress());
        require(_protocolId != bytes4(0), InvalidProtocolId());

        GATEWAY = _gateway;
        PROTOCOL_ID = _protocolId;
        ACCOUNTANT = IProtocolController(_protocolController).accountant(_protocolId);
        REWARD_TOKEN = IAccountant(ACCOUNTANT).REWARD_TOKEN();
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);

        // L2 optimization: Gateway can act as both transaction executor and token holder
        if (_locker == address(0)) {
            LOCKER = GATEWAY;
        } else {
            LOCKER = _locker;
        }
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Executes privileged transactions through the Safe module system
    /// @dev Handles two execution patterns:
    ///      - Mainnet: Gateway -> Locker -> Target (locker holds funds and executes)
    ///      - L2: Gateway acts as locker and executes directly on target
    /// @param target The address of the contract to interact with
    /// @param data The calldata to send to the target
    /// @return success Whether the transaction executed successfully
    function _executeTransaction(address target, bytes memory data) internal returns (bool success) {
        if (LOCKER == GATEWAY) {
            // L2 pattern: Gateway holds funds and executes directly
            success = IModuleManager(GATEWAY).execTransactionFromModule(target, 0, data, IModuleManager.Operation.Call);
        } else {
            // Mainnet pattern: Gateway instructs locker (which holds funds) to execute
            // The locker contract has the necessary approvals and balances
            success = IModuleManager(GATEWAY).execTransactionFromModule(
                LOCKER,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                IModuleManager.Operation.Call
            );
        }
    }
}
