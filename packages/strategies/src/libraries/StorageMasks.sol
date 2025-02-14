// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title StorageMasks
/// @notice Library containing bit masks for storage optimization
library StorageMasks {
    /// @notice Bit masks for vault supplyAndIntegralSlot
    /// @dev [supply (128) | integral (128)]
    uint256 constant SUPPLY = (1 << 128) - 1;
    uint256 constant INTEGRAL = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for account balanceAndIntegralSlot
    /// @dev balanceAndIntegralSlot: [balance (128) | integral (128)]
    uint256 constant BALANCE = (1 << 128) - 1;
    uint256 constant ACCOUNT_INTEGRAL = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for fees
    /// @dev [totalFeePercent (64) | protocolFeePercent (64) | harvestFeePercent (64)]
    uint256 constant TOTAL_FEE = ((1 << 64) - 1) << 128;
    uint256 constant PROTOCOL_FEE = ((1 << 64) - 1) << 64;
    uint256 constant HARVEST_FEE = (1 << 64) - 1;

    /// @notice Bit masks for RewardVault slot 1
    /// @dev [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    uint256 constant REWARD_DISTRIBUTOR = (1 << 160) - 1;
    uint256 constant REWARD_DURATION = ((1 << 32) - 1) << 160;
    uint256 constant REWARD_LAST_UPDATE = ((1 << 32) - 1) << 192;
    uint256 constant REWARD_PERIOD_FINISH = ((1 << 32) - 1) << 224;

    /// @notice Bit masks for RewardVault slot 2
    /// @dev [rewardRate (128) | rewardPerTokenStored (128)]
    uint256 constant REWARD_RATE = ((1 << 128) - 1) << 128;
    uint256 constant REWARD_PER_TOKEN_STORED = (1 << 128) - 1;

    /// @notice Bit masks for RewardVault account data
    /// @dev [rewardPerTokenPaid (128) | claimable (128)]
    uint256 constant ACCOUNT_REWARD_PER_TOKEN = (1 << 128) - 1;
    uint256 constant ACCOUNT_CLAIMABLE = ((1 << 128) - 1) << 128;
}
