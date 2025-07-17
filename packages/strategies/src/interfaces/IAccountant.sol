// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {IStrategy} from "src/interfaces/IStrategy.sol";

/// @notice Tracks reward and supply data for each vault
/// @dev Packed struct to minimize storage costs (3 storage slots)
struct VaultData {
    uint256 integral; // Cumulative reward per token (scaled by SCALING_FACTOR)
    uint128 supply; // Total supply of vault tokens
    uint128 feeSubjectAmount; // Amount of rewards subject to fees
    uint128 totalAmount; // Total reward amount including fee-exempt rewards
    uint128 netCredited; // Net rewards already credited to users (after fees)
    uint128 reservedHarvestFee; // Harvest fees reserved but not yet paid out
    uint128 reservedProtocolFee; // Protocol fees reserved but not yet accrued
}

interface IAccountant {
    /// @notice Tracks individual user positions within a vault
    /// @dev Integral tracking enables O(1) reward calculations
    struct AccountData {
        uint128 balance; // User's token balance in the vault
        uint256 integral; // Last integral value when user's rewards were updated
        uint256 pendingRewards; // Rewards earned but not yet claimed
    }

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

    function getPendingRewards(address vault) external view returns (uint128);
    function getPendingRewards(address vault, address account) external view returns (uint256);

    function vaults(address vault) external view returns (VaultData memory);
    function accounts(address vault, address account) external view returns (AccountData memory);

    function SCALING_FACTOR() external view returns (uint128);
}
