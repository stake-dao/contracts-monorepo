// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/interfaces/IAllocator.sol";

interface IStrategy {
    function deposit(IAllocator.Allocation memory allocation) external returns (uint256 pendingRewards);
    function withdraw(IAllocator.Allocation memory allocation) external returns (uint256 pendingRewards);

    function pendingRewards(address asset) external view returns (uint256);
}
