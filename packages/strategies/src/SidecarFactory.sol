// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title SidecarFactory.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org

/// @notice SidecarFactory is an abstract base factory contract for deploying protocol-specific sidecar instances.
///         It creates deterministic minimal proxies for sidecar implementations, enabling efficient deployment
///         of multiple sidecars with minimal gas costs.
abstract contract SidecarFactory is ISidecarFactory {
    /// @notice The protocol ID
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The protocol controller address
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice The implementation address
    address public immutable IMPLEMENTATION;

    /// @notice Mapping of gauges to sidecars
    mapping(address => address) public sidecar;

    /// @notice Error emitted when the gauge is invalid
    error InvalidGauge();

    /// @notice Error emitted when the token is invalid
    error InvalidToken();

    /// @notice Error emitted when a zero address is provided
    error ZeroAddress();

    /// @notice Error emitted when a protocol ID is zero
    error InvalidProtocolId();

    /// @notice Error emitted when the sidecar is already deployed
    error SidecarAlreadyDeployed();

    /// @notice Event emitted when a new sidecar is created
    /// @param gauge Address of the gauge
    /// @param sidecar Address of the created sidecar
    /// @param args Additional arguments used for creation
    event SidecarCreated(address indexed gauge, address indexed sidecar, bytes args);

    /// @notice Constructor
    /// @param _implementation Address of the sidecar implementation
    /// @param _protocolController Address of the protocol controller
    /// @param _protocolId Protocol ID
    constructor(bytes4 _protocolId, address _implementation, address _protocolController) {
        require(_implementation != address(0) && _protocolController != address(0), ZeroAddress());
        require(_protocolId != bytes4(0), InvalidProtocolId());

        PROTOCOL_ID = _protocolId;
        IMPLEMENTATION = _implementation;
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
    }

    /// @notice Create a new sidecar for a gauge
    /// @param gauge Gauge address
    /// @param args Encoded arguments for sidecar creation
    /// @return sidecarAddress Address of the created sidecar
    function create(address gauge, bytes memory args) public virtual override returns (address sidecarAddress) {
        require(sidecar[gauge] == address(0), SidecarAlreadyDeployed());

        // Validate the gauge and args
        _isValidGauge(gauge, args);

        // Create the sidecar
        sidecarAddress = _create(gauge, args);

        // Store the sidecar address
        sidecar[gauge] = sidecarAddress;

        emit SidecarCreated(gauge, sidecarAddress, args);
    }

    /// @notice Validates the gauge and arguments
    /// @dev Must be implemented by derived factories to handle protocol-specific validation
    /// @param gauge The gauge to validate
    /// @param args The arguments to validate
    function _isValidGauge(address gauge, bytes memory args) internal virtual;

    /// @notice Creates a sidecar for a gauge
    /// @dev Must be implemented by derived factories to handle protocol-specific sidecar creation
    /// @param gauge The gauge to create a sidecar for
    /// @param args The arguments for sidecar creation
    /// @return sidecarAddress Address of the created sidecar
    function _create(address gauge, bytes memory args) internal virtual returns (address sidecarAddress);
}
