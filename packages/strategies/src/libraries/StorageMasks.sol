// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title StorageMasks
/// @notice Library containing bit masks for storage optimization
library StorageMasks {
    /// @notice Bit masks for vault supplyAndIntegralSlot
    /// @dev [supply (128) | integral (128)]
    uint256 constant SUPPLY_MASK = (1 << 128) - 1;
    uint256 constant INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for donation data
    /// @dev [donation (128) | integral (128)]
    uint256 constant DONATION_MASK = (1 << 128) - 1;
    uint256 constant DONATION_INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @notice Bit masks for account balanceAndRewardsSlot
    /// @dev [balance (96) | integral (96) | pendingRewards (64)]
    uint256 constant BALANCE_MASK = (1 << 96) - 1;
    uint256 constant ACCOUNT_INTEGRAL_MASK = ((1 << 96) - 1) << 96;
    uint256 constant ACCOUNT_PENDING_REWARDS_MASK = ((1 << 64) - 1) << 192;

    /// @notice Bit masks for fees
    /// @dev [harvestFeePercent (16) | donationPremiumPercent (16) | protocolFeePercent (16)]
    uint256 constant HARVEST_FEE_MASK = (1 << 16) - 1;
    uint256 constant DONATION_FEE_MASK = ((1 << 16) - 1) << 16;
    uint256 constant PROTOCOL_FEE_MASK = ((1 << 16) - 1) << 32;
}
