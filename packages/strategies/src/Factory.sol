// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {RewardVault} from "src/RewardVault.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

abstract contract Factory is ProtocolContext {
    /// @notice Accountant address
    address public immutable ACCOUNTANT;

    /// @notice Main reward token address
    address public immutable REWARD_TOKEN;

    /// @notice Reward vault implementation address
    address public immutable REWARD_VAULT_IMPLEMENTATION;

    /// @notice Thrown if the gauge is not a valid candidate
    error InvalidGauge();

    /// @notice Thrown if the token is not valid
    error InvalidToken();

    /// @notice Thrown if the deployment is not valid
    error InvalidDeployment();

    /// @notice Thrown if the gauge has been already used
    error GaugeAlreadyUsed();

    /// @notice Emitted when a new vault is deployed
    event VaultDeployed(address vault, address asset, address gauge);

    /// @notice Constructor
    /// @param _protocolController Address of the protocol controller
    /// @param _rewardToken Address of the main reward token
    /// @param _vaultImplementation Address of the reward vault implementation
    /// @param _protocolId Protocol identifier
    constructor(address _protocolController, address _rewardToken, address _vaultImplementation, bytes4 _protocolId) {
        PROTOCOL_ID = _protocolId;
        REWARD_TOKEN = _rewardToken;
        REWARD_VAULT_IMPLEMENTATION = _vaultImplementation;
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);

        ACCOUNTANT = PROTOCOL_CONTROLLER.accountant(PROTOCOL_ID);
    }

    /// @notice Create a new vault for a given gauge
    /// @param _gauge Address of the gauge
    /// @return vault Address of the deployed vault
    function createVault(address _gauge) public virtual returns (address vault) {
        // Perform checks on the gauge to make sure it's valid and can be used
        require(_isValidGauge(_gauge), InvalidGauge());
        require(_isValidDeployment(_gauge), InvalidDeployment());
        require(PROTOCOL_CONTROLLER.vaults(_gauge) == address(0), GaugeAlreadyUsed());

        /// @dev Get the asset address from the gauge
        address _asset = _getAsset(_gauge);

        // Prepare the initialization data for the vault
        // The vault needs: registry, accountant, gauge, and asset
        bytes memory vaultData = abi.encodePacked(address(PROTOCOL_CONTROLLER), ACCOUNTANT, _gauge, _asset);

        // Generate a deterministic salt based on the gauge and asset
        bytes32 salt = keccak256(abi.encodePacked(_asset, _gauge));

        // Clone the vault implementation with the initialization data
        vault = Clones.cloneDeterministic(REWARD_VAULT_IMPLEMENTATION, salt);

        // Deploy Reward Receiver.
        // address rewardReceiver = address(new RewardReceiver(vault, ACCOUNTANT));

        // Register the vault in the protocol controller
        _registerVault(_gauge, vault, _asset);

        // Add reward tokens to the vault
        _setupRewardTokens(vault, _gauge);

        emit VaultDeployed(vault, _asset, _gauge);
    }

    /// @notice Sync reward tokens for a gauge
    /// @param _gauge Address of the gauge
    function syncRewardTokens(address _gauge) external {
        address vault = PROTOCOL_CONTROLLER.vaults(_gauge);
        require(vault != address(0), InvalidGauge());

        _setupRewardTokens(vault, _gauge);
    }

    function _getAsset(address _gauge) internal view virtual returns (address);

    function _isValidDeployment(address) internal view virtual returns (bool) {
        return true;
    }

    /// @notice Register the vault in the protocol controller
    /// @param _gauge Address of the gauge
    /// @param _vault Address of the vault
    /// @param _asset Address of the asset
    function _registerVault(address _gauge, address _vault, address _asset) internal {
        PROTOCOL_CONTROLLER.registerVault(_gauge, _vault, _asset, address(this), PROTOCOL_ID);
    }

    /// @notice Setup reward tokens for the vault
    /// @param _vault Address of the vault
    /// @param _gauge Address of the gauge
    function _setupRewardTokens(address _vault, address _gauge) internal virtual;

    /// @notice Check if a gauge is valid
    /// @param _gauge Address of the gauge
    /// @return isValid True if the gauge is valid
    function _isValidGauge(address _gauge) internal view virtual returns (bool);

    /// @notice Check if a token is valid as a reward token
    /// @param _token Address of the token
    /// @return isValid True if the token is valid
    function _isValidToken(address _token) internal view virtual returns (bool) {
        return _token != address(0) && _token != REWARD_TOKEN;
    }
}
