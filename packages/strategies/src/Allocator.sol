// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Allocator
/// @author Stake DAO
/// @notice Handles optimal distribution of deposited funds across multiple yield strategies
/// @dev This is a base contract that implements the IAllocator interface. It provides a simple
/// allocation strategy that directs all funds to a single gateway. More complex allocation
/// strategies can be implemented by inheriting from this contract and overriding the allocation
/// functions.
contract Allocator is IAllocator {
    /// @notice The address of the locker contract
    /// @dev This is the contract that holds tokens for staking.
    address public immutable LOCKER;

    /// @notice The address of the gateway contract
    /// @dev This is the contract that handles the actual deposit/withdrawal operations.
    address public immutable GATEWAY;

    /// @notice Flag indicating whether the allocation is harvested
    /// @dev If true, rewards are harvested during operations
    bool public immutable HARVESTED;

    /// @notice Initializes the Allocator contract
    /// @param _locker The address of the locker contract (can be address(0) for L2s)
    /// @param _gateway The address of the gateway contract
    /// @dev If _locker is address(0), LOCKER will be set to the same address as GATEWAY
    constructor(address _locker, address _gateway) {
        GATEWAY = _gateway;

        /// In some cases (L2s), the locker is the same as the gateway.
        if (_locker == address(0)) {
            LOCKER = GATEWAY;
        } else {
            LOCKER = _locker;
        }
    }

    /// @notice Determines how funds should be allocated during a deposit
    /// @param gauge The address of the gauge contract
    /// @param amount The amount of tokens to deposit
    /// @return Allocation struct containing the allocation details
    /// @dev In this base implementation, all funds are directed to the LOCKER
    function getDepositAllocation(address gauge, uint256 amount) public view virtual returns (Allocation memory) {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({gauge: gauge, targets: targets, amounts: amounts, harvested: HARVESTED});
    }

    /// @notice Determines how funds should be allocated during a withdrawal
    /// @param gauge The address of the gauge contract
    /// @param amount The amount of tokens to withdraw
    /// @return Allocation struct containing the allocation details
    /// @dev In this base implementation, all funds are withdrawn from the LOCKER
    function getWithdrawalAllocation(address gauge, uint256 amount) public view virtual returns (Allocation memory) {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({gauge: gauge, targets: targets, amounts: amounts, harvested: HARVESTED});
    }

    /// @notice Determines how funds should be allocated during a rebalance
    /// @param gauge The address of the gauge contract
    /// @param amount The amount of tokens to rebalance
    /// @return Allocation struct containing the allocation details
    /// @dev In this base implementation, rebalancing uses the same allocation as deposits
    function getRebalancedAllocation(address gauge, uint256 amount) public view virtual returns (Allocation memory) {
        return getDepositAllocation(gauge, amount);
    }

    /// @notice Returns the list of target addresses for a specific gauge
    /// gauge The address of the gauge contract (unused in this implementation)
    /// @return An array containing the target addresses
    /// @dev In this base implementation, the only target is the LOCKER
    function getAllocationTargets(address /*gauge*/) public view virtual returns (address[] memory) {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        return targets;
    }
}
