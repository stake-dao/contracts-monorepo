// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IStrategy} from "src/interfaces/IStrategy.sol";

interface IAccountant {
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint256 amount,
        IStrategy.PendingRewards memory pendingRewards,
        bool claimed
    ) external;

    function totalSupply(address asset) external view returns (uint256);
    function balanceOf(address asset, address account) external view returns (uint256);

    function claim(address[] calldata vaults, address receiver) external;
    function claim(address[] calldata vaults, address account, address receiver) external;
    function claimProtocolFees() external;
    function harvest(address vault) external;
}
