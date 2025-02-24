// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IAllocator {
    struct Allocation {
        address gauge;
        address[] targets;
        uint256[] amounts;
        bool harvested;
    }

    function getDepositAllocation(address asset, uint256 amount) external view returns (Allocation memory);
    function getWithdrawAllocation(address asset, uint256 amount) external view returns (Allocation memory);
}
