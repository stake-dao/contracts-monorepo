// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccountant} from "src/interfaces/IAccountant.sol";

contract MockAccountant is IAccountant {
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint256 amount,
        bool softCheckpoint,
        uint256 pendingRewards
    ) external override {
        // TODO: Implement checkpoint logic
    }

    function totalSupply(address asset) external view override returns (uint256) {
        return 0;
    }

    function balanceOf(address asset, address account) external view override returns (uint256) {
        return 0;
    }
}
