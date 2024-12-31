// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAllocator {
    struct Allocation {
        address gauge;
        address[] targets;
        uint256[] amounts;
    }

    function getDepositAllocations(address asset, uint256 amount) external view returns (Allocation memory);
    function getWithdrawAllocations(address asset, uint256 amount) external view returns (Allocation memory);
}
