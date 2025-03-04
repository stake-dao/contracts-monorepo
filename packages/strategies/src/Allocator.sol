// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Allocator
/// @author Stake DAO
/// @notice Handles optimal distribution of deposited funds across multiple yield strategies
contract Allocator is IAllocator {
    function getDepositAllocation(address asset, uint256 amount) public view virtual returns (Allocation memory) {}
    function getWithdrawalAllocation(address asset, uint256 amount) public view virtual returns (Allocation memory) {}
    function getRebalancedAllocation(address asset, uint256 amount) public view virtual returns (Allocation memory) {}

    function getAllocationTargets(address asset) public view virtual returns (address[] memory) {}
}
