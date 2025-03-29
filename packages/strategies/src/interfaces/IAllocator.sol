// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IAllocator {
    struct Allocation {
        address asset;
        address gauge;
        address[] targets;
        uint256[] amounts;
    }

    function getDepositAllocation(address asset, address gauge, uint256 amount)
        external
        view
        returns (Allocation memory);
    function getWithdrawalAllocation(address asset, address gauge, uint256 amount)
        external
        view
        returns (Allocation memory);
    function getRebalancedAllocation(address asset, address gauge, uint256 amount)
        external
        view
        returns (Allocation memory);

    function getAllocationTargets(address gauge) external view returns (address[] memory);
}
