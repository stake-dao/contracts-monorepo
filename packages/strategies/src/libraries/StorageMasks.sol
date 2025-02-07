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
}
