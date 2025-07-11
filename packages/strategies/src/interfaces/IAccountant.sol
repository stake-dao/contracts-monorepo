// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IStrategy} from "src/interfaces/IStrategy.sol";

interface IAccountant {
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards calldata pendingRewards,
        IStrategy.HarvestPolicy policy
    ) external;

    function checkpoint(
        address gauge,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards calldata pendingRewards,
        IStrategy.HarvestPolicy policy,
        address referrer
    ) external;

    function totalSupply(address asset) external view returns (uint128);
    function balanceOf(address asset, address account) external view returns (uint128);

    function claim(address[] calldata _gauges, bytes[] calldata harvestData) external;
    function claim(address[] calldata _gauges, bytes[] calldata harvestData, address receiver) external;
    function claim(address[] calldata _gauges, address account, bytes[] calldata harvestData, address receiver)
        external;

    function claimProtocolFees() external;
    function harvest(address[] calldata _gauges, bytes[] calldata _harvestData, address _receiver) external;

    function REWARD_TOKEN() external view returns (address);
}
