// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Harvester
/// @author Stake DAO
/// @notice Contract implementing the IHarvester interface for harvesting rewards from gauges
abstract contract Harvester is IHarvester {
    using SafeCast for uint256;

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The protocol identifier
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The locker contract
    address public immutable LOCKER;

    /// @notice The protocol controller contract
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the locker address is zero
    error ZeroAddress();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructs the Harvester contract
    /// @param _protocolId The protocol identifier
    /// @param _protocolController The protocol controller contract address
    /// @param _locker The locker contract address
    /// @custom:throws ZeroAddress If the locker address is zero
    constructor(bytes4 _protocolId, address _protocolController, address _locker) {
        require(_locker != address(0) && _protocolController != address(0), ZeroAddress());

        LOCKER = _locker;
        PROTOCOL_ID = _protocolId;
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
    }

    //////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Harvests rewards from a gauge
    /// @param gauge The gauge address to harvest from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards after harvesting
    /// @dev Called using delegatecall from the Accountant contract
    /// @dev Essentialy the same implementation as Strategy.sync() but this function claims rewards and returns them
    function harvest(address gauge, bytes calldata extraData)
        external
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        uint256 pendingRewardsAmount;
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                pendingRewardsAmount = _harvestRewards(gauge, extraData);
                pendingRewards.feeSubjectAmount = pendingRewardsAmount.toUint128();
            } else {
                pendingRewardsAmount = ISidecar(target).claim();
            }

            pendingRewards.totalAmount += pendingRewardsAmount.toUint128();
        }

        return pendingRewards;
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal function to harvest rewards from a gauge
    /// @dev This function should be overridden by protocol-specific implementations
    /// @param gauge The gauge address to harvest from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards after harvesting
    function _harvestRewards(address gauge, bytes calldata extraData)
        internal
        virtual
        returns (uint128 pendingRewards);
}
