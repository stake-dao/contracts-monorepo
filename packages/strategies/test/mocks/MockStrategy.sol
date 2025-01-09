// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    function deposit(IAllocator.Allocation memory allocation, bool preCheckpointRewards)
        external
        override
        returns (uint256)
    {
        return 0;
    }

    function withdraw(IAllocator.Allocation memory allocation, bool preCheckpointRewards)
        external
        override
        returns (uint256)
    {
        return 0;
    }

    function pendingRewards(address account) external view override returns (uint256) {
        return 0;
    }
}
