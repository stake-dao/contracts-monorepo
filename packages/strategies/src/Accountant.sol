/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/interfaces/IRegistry.sol";

/// @notice The source of truth.
contract Accountant {
    /// @notice Packed vault data structure into 2 slots for gas optimization
    /// @dev supplyAndIntegralSlot: [supply (128) | integral (128)]
    /// @dev timeAndRewardsSlot: [lastUpdateTime (64) | pendingRewards (64)]
    struct PackedVault {
        uint256 supplyAndIntegralSlot; // slot1 -> supplyAndIntegralSlot
        uint128 timeAndRewardsSlot; // slot2 -> timeAndRewardsSlot
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev balanceAndRewardsSlot: [balance (96) | integral (96) | pendingRewards (64)]
    struct PackedAccount {
        uint256 balanceAndRewardsSlot; // slot -> balanceAndRewardsSlot
    }

    /// @dev Bit masks for vault supplyAndIntegralSlot
    uint256 private constant SUPPLY_MASK = (1 << 128) - 1;
    uint256 private constant INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @dev Bit masks for vault timeAndRewardsSlot
    uint128 private constant LAST_UPDATE_TIME_MASK = (1 << 64) - 1;
    uint128 private constant PENDING_REWARDS_MASK = ((1 << 64) - 1) << 64;

    /// @dev Bit masks for account balanceAndRewardsSlot
    uint256 private constant BALANCE_MASK = (1 << 96) - 1;
    uint256 private constant ACCOUNT_INTEGRAL_MASK = ((1 << 96) - 1) << 96;
    uint256 private constant ACCOUNT_PENDING_REWARDS_MASK = ((1 << 64) - 1) << 192;

    /// @notice The registry of vaults.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice Whether the vault integral is updated before the accounts checkpoint.
    /// @notice Supply of vaults.
    /// @dev Vault address -> PackedVault.
    mapping(address => PackedVault) private vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> PackedAccount.
    mapping(address => mapping(address => PackedAccount)) private accounts;

    /// @notice The error thrown when the caller is not a vault.
    error OnlyVault();

    constructor(address _registry, address _rewardToken) {
        REGISTRY = _registry;
        REWARD_TOKEN = _rewardToken;
    }

    /// @notice Function called by vaults to checkpoint the state of the vault on every account action.
    /// @param asset The asset address.
    /// @param from The address of the sender.
    /// @param to The address of the receiver.
    /// @param amount The amount of tokens transferred.
    /// @param pendingRewards The amount of pending rewards.
    function checkpoint(address asset, address from, address to, uint256 amount, uint256 pendingRewards) external {
        if (msg.sender != IRegistry(REGISTRY).vaults(asset)) revert OnlyVault();

        PackedVault storage _vault = vaults[msg.sender];
        uint256 vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;
        // uint128 vaultTimeAndRewards = _vault.timeAndRewardsSlot;

        uint256 supply = uint128(vaultSupplyAndIntegral & SUPPLY_MASK);
        uint256 integral = uint128((vaultSupplyAndIntegral & INTEGRAL_MASK) >> 128);

        if (pendingRewards > 0) {
            integral += uint128(pendingRewards * 1e18 / supply);
        }

        /// 1. Minting.
        if (from == address(0)) {
            supply += amount;
        }
        /// 2. Transferring. Update the "from" account.
        else {
            PackedAccount storage _from = accounts[msg.sender][from];
            uint256 fromBalanceAndRewards = _from.balanceAndRewardsSlot;
            uint256 fromBalance = uint96(fromBalanceAndRewards & BALANCE_MASK);
            uint256 fromIntegral = uint96((fromBalanceAndRewards & ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 fromPendingRewards = uint64((fromBalanceAndRewards & ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            fromPendingRewards += uint64((integral - fromIntegral) * fromBalance / supply);
            fromBalance -= amount;

            _from.balanceAndRewardsSlot = (fromBalance & BALANCE_MASK) | ((integral << 96) & ACCOUNT_INTEGRAL_MASK)
                | ((fromPendingRewards << 192) & ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// 3. Burning.
        if (to == address(0)) {
            supply -= amount;
        }
        /// 4. Transferring. Update the "to" account.
        else {
            PackedAccount storage _to = accounts[msg.sender][to];
            uint256 toBalanceAndRewards = _to.balanceAndRewardsSlot;
            uint256 toBalance = uint96(toBalanceAndRewards & BALANCE_MASK);
            uint256 toIntegral = uint96((toBalanceAndRewards & ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 toPendingRewards = uint64((toBalanceAndRewards & ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            toPendingRewards += uint64((integral - toIntegral) * toBalance / supply);
            toBalance += amount;

            _to.balanceAndRewardsSlot = (toBalance & BALANCE_MASK) | ((integral << 96) & ACCOUNT_INTEGRAL_MASK)
                | ((toPendingRewards << 192) & ACCOUNT_PENDING_REWARDS_MASK);
        }

        // Update vault storage
        _vault.supplyAndIntegralSlot = (supply & SUPPLY_MASK) | ((integral << 128) & INTEGRAL_MASK);
    }

    function totalSupply(address vault) external view returns (uint256) {
        return uint128(vaults[vault].supplyAndIntegralSlot & SUPPLY_MASK);
    }

    function balanceOf(address vault, address account) external view returns (uint256) {
        return uint96(accounts[vault][account].balanceAndRewardsSlot & BALANCE_MASK);
    }
}