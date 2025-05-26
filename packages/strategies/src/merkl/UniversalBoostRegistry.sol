// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title UniversalBoostRegistry - Registry for StakeDAO Boosts renting.
/// @notice A registry to keep track of the Boosts rented by the users, per protocol, to work with Merkl.
/// @dev Merkl will use this registry to know which Boosts are rented by the users, per protocol, and allocate according rewards,
///      minus the protocol fees (if any), set by this contract.
///      
///      Key responsibilities:
///      - Tracks boost rental status for users across different protocols
///      - Manages protocol-specific fee configurations with time-delayed updates
///      - Provides a secure fee update mechanism with owner controls and delay periods
///      - Integrates with Merkl for reward distribution calculations
///
///      The contract implements a two-phase fee update system:
///      1. Queue: Owner queues new protocol configurations
///      2. Commit: After delay period, configurations can be committed to take effect
contract UniversalBoostRegistry is Ownable2Step {

    //////////////////////////////////////////////////////
    // --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Configuration parameters for a specific protocol.
    /// @dev Contains fee percentage, fee receiver address, and timestamp for delay mechanism.
    struct ProtocolConfig {
        /// @notice Fee percentage charged by the protocol (scaled by 1e18).
        uint256 protocolFees;
        /// @notice Address that receives the protocol fees.
        address feeReceiver;
        /// @notice Timestamp when this configuration was last updated.
        uint256 lastUpdated;
    }

    //////////////////////////////////////////////////////
    // --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice The maximum fee percent (40%).
    uint256 public constant MAX_FEE_PERCENT = 0.4e18;

    /// @notice Delay period for new fees to take effect.
    /// @dev This prevents immediate fee changes and provides users time to react to fee updates.
    uint256 public constant DELAY_PERIOD = 1 days;

    //////////////////////////////////////////////////////
    // --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice Mapping of protocol ID to queued protocol configuration.
    /// @dev These are pending configurations that haven't taken effect yet.
    mapping(bytes4 protocolId => ProtocolConfig config) public queueProtocolConfig;

    /// @notice Mapping of protocol ID to active protocol configuration.
    /// @dev These are the currently active configurations used for fee calculations.
    mapping(bytes4 protocolId => ProtocolConfig config) public protocolConfig;

    /// @notice Mapping of account to protocol ID to boost rental status.
    /// @dev Tracks whether a user has rented a boost for a specific protocol.
    ///      True means the user is currently renting a boost, false means they are not.
    mapping(address account => mapping(bytes4 protocolId => bool status)) public isRentingBoost;

    //////////////////////////////////////////////////////
    // --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Event emitted when a boost is rented.
    /// @param account The address that rented the boost.
    /// @param protocolId The protocol ID for which the boost was rented.
    event BoostRented(address indexed account, bytes4 indexed protocolId);

    /// @notice Event emitted when a boost is returned.
    /// @param account The address that returned the boost.
    /// @param protocolId The protocol ID for which the boost was returned.
    event BoostReturned(address indexed account, bytes4 indexed protocolId);

    /// @notice Event emitted when a new protocol config is queued.
    /// @param protocolId The protocol ID for which the config was queued.
    /// @param config The queued protocol configuration.
    event NewProtocolConfigQueued(bytes4 indexed protocolId, ProtocolConfig config);

    /// @notice Event emitted when a protocol config is committed.
    /// @param protocolId The protocol ID for which the config was committed.
    /// @param config The committed protocol configuration.
    event ProtocolConfigCommitted(bytes4 indexed protocolId, ProtocolConfig config);

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when a fee exceeds the maximum allowed.
    error FeeExceedsMaximum();

    /// @notice Error thrown when the delay period for new fees to take effect has not passed.
    error DelayPeriodNotPassed();


    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the UniversalBoostRegistry contract.
    /// @dev Sets the deployer as the initial owner using Ownable2Step pattern.
    constructor() Ownable(msg.sender) {}

    //////////////////////////////////////////////////////
    // --- BOOST RENTAL OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Rents a boost for a given protocol.
    /// @dev Updates the rental status to true and emits a BoostRented event.
    ///      This function can be called by any user to rent a boost for themselves.
    /// @param protocolId The protocol ID for which to rent the boost.
    function rentBoost(bytes4 protocolId) public {
        // Update the rental status for the caller and protocol
        isRentingBoost[msg.sender][protocolId] = true;
        
        // Emit event for off-chain tracking and Merkl integration
        emit BoostRented(msg.sender, protocolId);
    }

    /// @notice Returns a boost for a given protocol.
    /// @dev Updates the rental status to false and emits a BoostReturned event.
    ///      This function can be called by any user to return their rented boost.
    /// @param protocolId The protocol ID for which to return the boost.
    function returnBoost(bytes4 protocolId) public {
        // Update the rental status for the caller and protocol
        isRentingBoost[msg.sender][protocolId] = false;
        
        // Emit event for off-chain tracking and Merkl integration
        emit BoostReturned(msg.sender, protocolId);
    }

    //////////////////////////////////////////////////////
    // --- PROTOCOL CONFIGURATION MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Queues a new protocol config for a given protocol ID.
    /// @dev Implements the first phase of the two-phase fee update mechanism.
    ///      Only the owner can queue new configurations. The configuration will not
    ///      take effect immediately - it must be committed after the delay period.
    /// @param protocolId The protocol ID for which to queue the new configuration.
    /// @param config The protocol configuration to queue.
    /// @custom:throws OwnableUnauthorizedAccount If caller is not the owner.
    /// @custom:throws FeeExceedsMaximum If the protocol fee exceeds the maximum allowed.
    function queueNewProtocolConfig(bytes4 protocolId, ProtocolConfig memory config) public onlyOwner {
        // Validate that the protocol fee doesn't exceed the maximum allowed
        require(config.protocolFees <= MAX_FEE_PERCENT, FeeExceedsMaximum());
        
        // Store the new configuration in the queue mapping
        queueProtocolConfig[protocolId] = config;

        // Emit event to notify about the queued configuration
        emit NewProtocolConfigQueued(protocolId, config);
    }

    /// @notice Commits a new protocol config for a given protocol ID.
    /// @dev Implements the second phase of the two-phase fee update mechanism.
    ///      Can only be called after the delay period has passed since the last update.
    ///      This function can be called by anyone once the delay period has elapsed.
    /// @param protocolId The protocol ID for which to commit the new configuration.
    /// @custom:throws DelayPeriodNotPassed If the delay period since last update hasn't elapsed.
    function commitProtocolConfig(bytes4 protocolId) public {
        // Ensure sufficient time has passed since the last configuration update
        require(block.timestamp - protocolConfig[protocolId].lastUpdated > DELAY_PERIOD, DelayPeriodNotPassed());

        // Retrieve the queued configuration
        ProtocolConfig memory newConfig = queueProtocolConfig[protocolId];
        
        // Update the timestamp to current block timestamp
        newConfig.lastUpdated = block.timestamp;

        // Emit event before updating storage for accurate event data
        emit ProtocolConfigCommitted(protocolId, protocolConfig[protocolId] = newConfig);

        // Clear the queued configuration as it's now active
        delete queueProtocolConfig[protocolId];
    }
}