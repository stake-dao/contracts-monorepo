// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title StorageMasks
/// @notice Library containing bit masks for storage optimization
library StorageMasks {
    /// @notice Bit masks for vault supplyAndIntegralSlot
    /// @dev [supply (128) | integral (128)]
    uint256 constant SUPPLY_MASK = (1 << 128) - 1;
    uint256 constant INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for account balanceAndIntegralSlot
    /// @dev balanceAndIntegralSlot: [balance (128) | integral (128)]
    uint256 constant BALANCE_MASK = (1 << 128) - 1;
    uint256 constant ACCOUNT_INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for fees
    /// @dev [totalFeePercent (64) | protocolFeePercent (64) | harvestFeePercent (64)]
    uint256 constant TOTAL_FEE_MASK = ((1 << 64) - 1) << 128;
    uint256 constant PROTOCOL_FEE_MASK = ((1 << 64) - 1) << 64;
    uint256 constant HARVEST_FEE_MASK = (1 << 64) - 1;

    /// @notice Bit masks for RewardVault slot 1
    /// @dev [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    uint256 constant REWARD_DISTRIBUTOR_MASK = (1 << 160) - 1;
    uint256 constant REWARD_DURATION_MASK = ((1 << 32) - 1) << 160;
    uint256 constant REWARD_LAST_UPDATE_MASK = ((1 << 32) - 1) << 192;
    uint256 constant REWARD_PERIOD_FINISH_MASK = ((1 << 32) - 1) << 224;

    /// @notice Bit masks for RewardVault slot 2
    /// @dev [rewardRate (96) | rewardPerTokenStored (160)]
    uint256 constant REWARD_PER_TOKEN_STORED_MASK = (1 << 160) - 1;
    uint256 constant REWARD_RATE_MASK = ((1 << 96) - 1) << 160;

    /// @notice Bit masks for RewardVault user data
    /// @dev [rewardPerTokenPaid (160) | claimable (48) | claimed (48)]
    uint256 constant USER_REWARD_PER_TOKEN_MASK = (1 << 160) - 1;
    uint256 constant USER_CLAIMABLE_MASK = ((1 << 48) - 1) << 160;
    uint256 constant USER_CLAIMED_MASK = ((1 << 48) - 1) << 208;
}
