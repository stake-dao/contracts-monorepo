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
    /// @dev Contains both active and queued fee configurations with timestamps for delay mechanism.
    ///      Optimized for gas efficiency by packing fields into 3 storage slots instead of 6.
    ///      Active values are used for current operations, queued values become active after commitment.
    struct ProtocolConfig {
        /// @notice Active fee percentage charged by the protocol (scaled by 1e18).
        uint128 protocolFees;
        /// @notice Queued fee percentage that will become active after commitment (scaled by 1e18).
        uint128 queuedProtocolFees;
        /// @notice Timestamp when this configuration was last committed and became active.
        uint64 lastUpdated;
        /// @notice Timestamp when a new configuration was queued (0 if not queued).
        /// @dev Used to track the delay period. Zero indicates no pending configuration.
        uint64 queuedTimestamp;
        /// @notice Active address that receives the protocol fees.
        address feeReceiver;
        /// @notice Queued address that will receive fees after commitment.
        address queuedFeeReceiver;
    }

    //////////////////////////////////////////////////////
    // --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice The maximum fee percent (40%).
    uint128 public constant MAX_FEE_PERCENT = 0.4e18;

    //////////////////////////////////////////////////////
    // --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice Delay period for new fees to take effect.
    /// @dev This prevents immediate fee changes and provides users time to react to fee updates.
    uint64 public delayPeriod = 1 days;

    /// @notice Queued delay period that will become active after commitment.
    uint64 public queuedDelayPeriod;

    /// @notice Timestamp when the queued delay period can be committed.
    uint64 public delayPeriodQueuedTimestamp;

    /// @notice Mapping of protocol ID to protocol configuration.
    /// @dev Contains both active and queued configurations in a single mapping.
    ///      Use queuedTimestamp to determine if a configuration is pending.
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
    /// @param protocolFees The queued protocol fee percentage.
    /// @param feeReceiver The queued fee receiver address.
    /// @param queuedTimestamp The timestamp when the configuration was queued.
    event NewProtocolConfigQueued(
        bytes4 indexed protocolId, uint128 protocolFees, address feeReceiver, uint64 queuedTimestamp
    );

    /// @notice Event emitted when a protocol config is committed.
    /// @param protocolId The protocol ID for which the config was committed.
    /// @param protocolFees The committed protocol fee percentage.
    /// @param feeReceiver The committed fee receiver address.
    /// @param committedTimestamp The timestamp when the configuration was committed.
    event ProtocolConfigCommitted(
        bytes4 indexed protocolId, uint128 protocolFees, address feeReceiver, uint64 committedTimestamp
    );

    /// @notice Event emitted when a new delay period is queued.
    /// @param newDelayPeriod The new delay period.
    /// @param queuedTimestamp The timestamp when it can be committed.
    event DelayPeriodQueued(uint64 newDelayPeriod, uint64 queuedTimestamp);

    /// @notice Event emitted when the delay period is committed.
    /// @param newDelayPeriod The new delay period.
    /// @param committedTimestamp The timestamp when it was committed.
    event DelayPeriodCommitted(uint64 newDelayPeriod, uint64 committedTimestamp);

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when there is no queued configuration to commit.
    error NoQueuedConfig();

    /// @notice Error thrown when a fee exceeds the maximum allowed.
    error FeeExceedsMaximum();

    /// @notice Error thrown when the delay period for new fees to take effect has not passed.
    error DelayPeriodNotPassed();

    /// @notice Error thrown when there is no queued delay period to commit.
    error NoQueuedDelayPeriod();

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the UniversalBoostRegistry contract.
    /// @dev Sets the deployer as the initial owner using Ownable2Step pattern.
    constructor(address initialOwner) Ownable(initialOwner) {}

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
    ///      Preserves active configuration values until commitment.
    /// @param protocolId The protocol ID for which to queue the new configuration.
    /// @param protocolFees The protocol fee percentage to queue (scaled by 1e18).
    /// @param feeReceiver The fee receiver address to queue.
    /// @custom:throws OwnableUnauthorizedAccount If caller is not the owner.
    /// @custom:throws FeeExceedsMaximum If the protocol fee exceeds the maximum allowed.
    function queueNewProtocolConfig(bytes4 protocolId, uint128 protocolFees, address feeReceiver) public onlyOwner {
        // Validate that the protocol fee doesn't exceed the maximum allowed
        require(protocolFees <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        // Get storage pointer to the configuration for gas efficiency
        ProtocolConfig storage config = protocolConfig[protocolId];

        // Update only the queued configuration fields, preserving active values
        uint64 currentTime = uint64(block.timestamp);
        config.queuedProtocolFees = protocolFees;
        config.queuedFeeReceiver = feeReceiver;
        config.queuedTimestamp = currentTime + delayPeriod;

        // Emit event to notify about the queued configuration
        emit NewProtocolConfigQueued(protocolId, protocolFees, feeReceiver, currentTime + delayPeriod);
    }

    /// @notice Queues a new delay period.
    /// @dev This function can only be called by the owner. The new delay period
    ///      will only take effect after the current delay period has passed.
    ///      This prevents bypassing the delay mechanism by reducing the delay period.
    /// @param newDelayPeriod The new delay period to queue.
    function queueDelayPeriod(uint64 newDelayPeriod) public onlyOwner {
        uint64 currentTime = uint64(block.timestamp);
        queuedDelayPeriod = newDelayPeriod;
        delayPeriodQueuedTimestamp = currentTime + delayPeriod;
        
        emit DelayPeriodQueued(newDelayPeriod, currentTime + delayPeriod);
    }

    /// @notice Commits the queued delay period.
    /// @dev Can be called by anyone once the delay period has passed.
    function commitDelayPeriod() public {
        require(delayPeriodQueuedTimestamp != 0, NoQueuedDelayPeriod());
        require(uint64(block.timestamp) >= delayPeriodQueuedTimestamp, DelayPeriodNotPassed());
        
        uint64 currentTime = uint64(block.timestamp);
        delayPeriod = queuedDelayPeriod;
        
        // Clear queued values
        queuedDelayPeriod = 0;
        delayPeriodQueuedTimestamp = 0;
        
        emit DelayPeriodCommitted(delayPeriod, currentTime);
    }

    /// @notice Commits a new protocol config for a given protocol ID.
    /// @dev Implements the second phase of the two-phase fee update mechanism.
    ///      Can only be called after the delay period has passed since the configuration was queued.
    ///      This function can be called by anyone once the delay period has elapsed.
    ///      Moves queued values to active values and clears the queue.
    /// @param protocolId The protocol ID for which to commit the new configuration.
    /// @custom:throws DelayPeriodNotPassed If the delay period since queuing hasn't elapsed.
    /// @custom:throws NoQueuedConfig If there is no queued configuration to commit.
    function commitProtocolConfig(bytes4 protocolId) public {
        // Get storage pointer to the configuration for gas efficiency
        ProtocolConfig storage config = protocolConfig[protocolId];

        // Ensure there is a queued configuration to commit
        require(config.queuedTimestamp != 0, NoQueuedConfig());

        // Ensure sufficient time has passed since the configuration was queued
        require(uint64(block.timestamp) >= config.queuedTimestamp, DelayPeriodNotPassed());

        // Move queued values to active values
        uint64 currentTime = uint64(block.timestamp);
        config.protocolFees = config.queuedProtocolFees;
        config.feeReceiver = config.queuedFeeReceiver;
        config.lastUpdated = currentTime;

        // Clear queued values to indicate no pending configuration
        config.queuedProtocolFees = 0;
        config.queuedFeeReceiver = address(0);
        config.queuedTimestamp = 0;

        // Emit event to notify about the committed configuration
        emit ProtocolConfigCommitted(protocolId, config.protocolFees, config.feeReceiver, currentTime);
    }

    //////////////////////////////////////////////////////
    // --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns whether a protocol configuration is currently queued and pending.
    /// @param protocolId The protocol ID to check.
    /// @return _ True if there is a queued configuration pending commitment.
    function hasQueuedConfig(bytes4 protocolId) external view returns (bool) {
        return protocolConfig[protocolId].queuedTimestamp != 0;
    }

    /// @notice Returns the timestamp when a configuration can be committed.
    /// @param protocolId The protocol ID to check.
    /// @return _ The timestamp when the configuration can be committed (0 if no queued config).
    function getCommitTimestamp(bytes4 protocolId) external view returns (uint64) {
        return protocolConfig[protocolId].queuedTimestamp;
    }

    /// @notice Returns whether a delay period is currently queued and pending.
    /// @return _ True if there is a queued delay period pending commitment.
    function hasQueuedDelayPeriod() external view returns (bool) {
        return delayPeriodQueuedTimestamp != 0;
    }

    /// @notice Returns the timestamp when the queued delay period can be committed.
    /// @return _ The timestamp when the delay period can be committed (0 if no queued delay period).
    function getDelayPeriodCommitTimestamp() external view returns (uint64) {
        return delayPeriodQueuedTimestamp;
    }
}
