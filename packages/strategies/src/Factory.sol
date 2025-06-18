// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";

/// @title Factory - Abstract Base Factory Contract
/// @notice A base contract for implementing protocol-specific vault factories
/// @dev Provides core functionality for creating and managing vaults across different protocols
///      Key responsibilities:
///      - Deploys vaults and reward receivers for protocol gauges
///      - Validates gauges and tokens
///      - Registers vaults with the protocol controller
///      - Sets up reward tokens for vaults
abstract contract Factory is ProtocolContext {
    //////////////////////////////////////////////////////
    // --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Reward vault implementation address
    /// @dev The implementation contract that will be cloned for each new vault
    address public immutable REWARD_VAULT_IMPLEMENTATION;

    /// @notice Reward receiver implementation address
    /// @dev The implementation contract that will be cloned for each new reward receiver
    address public immutable REWARD_RECEIVER_IMPLEMENTATION;

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the gauge is not a valid candidate
    error InvalidGauge();

    /// @notice Error thrown when the approve fails
    error ApproveFailed();

    /// @notice Error thrown when the token is not valid
    error InvalidToken();

    /// @notice Error thrown when the deployment is not valid
    error InvalidDeployment();

    /// @notice Error thrown when the gauge has been already used
    error AlreadyDeployed();

    //////////////////////////////////////////////////////
    // --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when a new vault is deployed
    /// @param vault Address of the deployed vault
    /// @param asset Address of the underlying asset
    /// @param gauge Address of the associated gauge
    event VaultDeployed(address vault, address asset, address gauge);

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the factory with protocol controller, reward token, and vault implementation
    /// @param _protocolController Address of the protocol controller
    /// @param _vaultImplementation Address of the reward vault implementation
    /// @param _rewardReceiverImplementation Address of the reward receiver implementation
    /// @param _protocolId Protocol identifier
    /// @param _locker Address of the locker
    /// @param _gateway Address of the gateway
    constructor(
        address _protocolController,
        address _vaultImplementation,
        address _rewardReceiverImplementation,
        bytes4 _protocolId,
        address _locker,
        address _gateway
    ) ProtocolContext(_protocolId, _protocolController, _locker, _gateway) {
        require(
            _protocolController != address(0) && _vaultImplementation != address(0)
                && _rewardReceiverImplementation != address(0),
            ZeroAddress()
        );

        REWARD_VAULT_IMPLEMENTATION = _vaultImplementation;
        REWARD_RECEIVER_IMPLEMENTATION = _rewardReceiverImplementation;
    }

    //////////////////////////////////////////////////////
    // --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Create a new vault for a given gauge
    /// @dev Deploys a vault and reward receiver for the gauge, registers them, and sets up reward tokens
    /// @param gauge Address of the gauge
    /// @return vault Address of the deployed vault
    /// @return rewardReceiver Address of the deployed reward receiver
    /// @custom:throws InvalidGauge If the gauge is not valid
    /// @custom:throws InvalidDeployment If the deployment is not valid
    /// @custom:throws GaugeAlreadyUsed If the gauge has already been used
    function createVault(address gauge) public virtual returns (address vault, address rewardReceiver) {
        /// Perform checks on the gauge to make sure it's valid and can be used
        require(_isValidGauge(gauge), InvalidGauge());
        require(_isValidDeployment(gauge), InvalidDeployment());
        require(PROTOCOL_CONTROLLER.vaults(gauge) == address(0), AlreadyDeployed());

        /// Get the asset address from the gauge
        address asset = _getAsset(gauge);

        /// Prepare the initialization data for the vault
        /// The vault needs: gauge and asset
        bytes memory data = abi.encodePacked(gauge, asset);

        /// Generate a deterministic salt based on the gauge and asset
        bytes32 salt = keccak256(data);

        /// Clone the vault implementation with the initialization data
        vault = Clones.cloneDeterministicWithImmutableArgs(REWARD_VAULT_IMPLEMENTATION, data, salt);

        /// Prepare the initialization data for the reward receiver
        /// The reward receiver needs: vault
        data = abi.encodePacked(vault);

        /// Generate a deterministic salt based on the vault
        salt = keccak256(abi.encodePacked(vault));

        /// Deploy Reward Receiver.
        rewardReceiver = Clones.cloneDeterministicWithImmutableArgs(REWARD_RECEIVER_IMPLEMENTATION, data, salt);

        /// Initialize the vault.
        /// @dev Can be approval if needed etc.
        _initializeVault(vault, asset, gauge);

        /// Register the vault in the protocol controller
        _registerVault(gauge, vault, asset, rewardReceiver);

        /// Add extra reward tokens to the vault
        _setupRewardTokens(vault, gauge, rewardReceiver);

        /// Set the reward receiver for the gauge
        _setRewardReceiver(gauge, rewardReceiver);

        /// Set the valid allocation target.
        PROTOCOL_CONTROLLER.setValidAllocationTarget(gauge, LOCKER);

        emit VaultDeployed(vault, asset, gauge);
    }

    /// @notice Sync reward tokens for a gauge
    /// @dev Updates the reward tokens for an existing vault
    /// @param gauge Address of the gauge
    /// @custom:throws InvalidGauge If the gauge is not valid or has no associated vault
    function syncRewardTokens(address gauge) external {
        address vault = PROTOCOL_CONTROLLER.vaults(gauge);
        require(vault != address(0), InvalidGauge());

        _setupRewardTokens(vault, gauge, PROTOCOL_CONTROLLER.rewardReceiver(gauge));
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Get the asset address from a gauge
    /// @dev Must be implemented by derived factories to handle protocol-specific asset retrieval
    /// @param gauge Address of the gauge
    /// @return The address of the asset associated with the gauge
    function _getAsset(address gauge) internal view virtual returns (address);

    /// @notice Check if a deployment is valid
    /// @dev Can be overridden by derived factories to add additional deployment validation
    /// @return True if the deployment is valid, false otherwise
    function _isValidDeployment(address) internal view virtual returns (bool) {
        return true;
    }

    /// @notice Initialize the vault
    /// @param vault Address of the vault
    /// @param asset Address of the asset
    /// @param gauge Address of the gauge
    function _initializeVault(address vault, address asset, address gauge) internal virtual;

    /// @notice Register the vault in the protocol controller
    /// @param gauge Address of the gauge
    /// @param vault Address of the vault
    /// @param asset Address of the asset
    /// @param rewardReceiver Address of the reward receiver
    function _registerVault(address gauge, address vault, address asset, address rewardReceiver) internal {
        PROTOCOL_CONTROLLER.registerVault(gauge, vault, asset, rewardReceiver, PROTOCOL_ID);
    }

    /// @notice Setup reward tokens for the vault
    /// @dev Must be implemented by derived factories to handle protocol-specific reward token setup
    /// @param vault Address of the vault
    /// @param gauge Address of the gauge
    /// @param rewardReceiver Address of the reward receiver
    function _setupRewardTokens(address vault, address gauge, address rewardReceiver) internal virtual;

    /// @notice Set the reward receiver for a gauge
    /// @dev Must be implemented by derived factories to handle protocol-specific reward receiver setup
    /// @param gauge Address of the gauge
    /// @param rewardReceiver Address of the reward receiver
    function _setRewardReceiver(address gauge, address rewardReceiver) internal virtual;

    /// @notice Check if a gauge is valid
    /// @dev Must be implemented by derived factories to handle protocol-specific gauge validation
    /// @param gauge Address of the gauge
    /// @return isValid True if the gauge is valid
    function _isValidGauge(address gauge) internal view virtual returns (bool);

    /// @notice Check if a token is valid as a reward token
    /// @dev Validates that the token is not zero address and not the main reward token
    /// @param token Address of the token
    /// @return isValid True if the token is valid
    function _isValidToken(address token) internal view virtual returns (bool) {
        return token != address(0) && token != REWARD_TOKEN;
    }
}
