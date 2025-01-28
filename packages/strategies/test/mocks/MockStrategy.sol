// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    function deposit(IAllocator.Allocation memory) external pure override returns (uint256) {
        return 0;
    }

    function withdraw(IAllocator.Allocation memory) external pure returns (uint256) {
        return 0;
    }

    function pendingRewards(address) external pure override returns (uint256) {
        return 0;
    }
}
