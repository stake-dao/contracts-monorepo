/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/interfaces/IRegistry.sol";

/// @notice The source of truth.
contract Accountant {
    /// @notice Packed vault data structure into 2 slots for gas optimization
    /// @dev Slot 1: [supply (128) | integral (128)]
    /// @dev Slot 2: [lastUpdateTime (64) | pendingRewards (64)]
    struct PackedVault {
        uint256 slot1;
        uint128 slot2;
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev [balance (96) | integral (96) | pendingRewards (64)]
    struct PackedAccount {
        uint256 slot;
    }

    /// @dev Bit masks for vault slot 1
    uint256 private constant SUPPLY_MASK = (1 << 128) - 1;
    uint256 private constant INTEGRAL_MASK = ((1 << 128) - 1) << 128;

    /// @dev Bit masks for vault slot 2
    uint128 private constant LAST_UPDATE_TIME_MASK = (1 << 64) - 1;
    uint128 private constant PENDING_REWARDS_MASK = ((1 << 64) - 1) << 64;

    /// @dev Bit masks for account slot
    uint256 private constant BALANCE_MASK = (1 << 96) - 1;
    uint256 private constant ACCOUNT_INTEGRAL_MASK = ((1 << 96) - 1) << 96;
    uint256 private constant ACCOUNT_PENDING_REWARDS_MASK = ((1 << 64) - 1) << 192;

    /// @notice The registry of vaults.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice Whether the vault integral is updated before the accounts checkpoint.
    bool public immutable PRE_CHECKPOINT_REWARDS;

    /// @notice Supply of vaults.
    /// @dev Vault address -> PackedVault.
    mapping(address => PackedVault) public vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> PackedAccount.
    mapping(address => mapping(address => PackedAccount)) public accounts;

    /// @notice The error thrown when the caller is not a vault.
    error OnlyVault();

    constructor(address _registry, address _rewardToken, bool _softCheckpoint) {
        REGISTRY = _registry;
        REWARD_TOKEN = _rewardToken;
        PRE_CHECKPOINT_REWARDS = _softCheckpoint;
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
        uint256 vaultSlot1 = _vault.slot1;
        // uint128 vaultSlot2 = _vault.slot2;

        uint256 supply = uint128(vaultSlot1 & SUPPLY_MASK);
        uint256 integral = uint128((vaultSlot1 & INTEGRAL_MASK) >> 128);

        /// 0. Update the vault integral with the pending rewards distributed.
        if (PRE_CHECKPOINT_REWARDS && pendingRewards > 0) {
            integral += uint128(pendingRewards * 1e18 / supply);
        }

        /// 1. Minting.
        if (from == address(0)) {
            supply += amount;
        }
        /// 2. Transferring. Update the "from" account.
        else {
            PackedAccount storage _from = accounts[msg.sender][from];
            uint256 fromSlot = _from.slot;
            uint256 fromBalance = uint96(fromSlot & BALANCE_MASK);
            uint256 fromIntegral = uint96((fromSlot & ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 fromPendingRewards = uint64((fromSlot & ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            fromPendingRewards += uint64((integral - fromIntegral) * fromBalance / supply);
            fromBalance -= amount;

            _from.slot = (fromBalance & BALANCE_MASK) | ((integral << 96) & ACCOUNT_INTEGRAL_MASK)
                | ((fromPendingRewards << 192) & ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// 3. Burning.
        if (to == address(0)) {
            supply -= amount;
        }
        /// 4. Transferring. Update the "to" account.
        else {
            PackedAccount storage _to = accounts[msg.sender][to];
            uint256 toSlot = _to.slot;
            uint256 toBalance = uint96(toSlot & BALANCE_MASK);
            uint256 toIntegral = uint96((toSlot & ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 toPendingRewards = uint64((toSlot & ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            toPendingRewards += uint64((integral - toIntegral) * toBalance / supply);
            toBalance += amount;

            _to.slot = (toBalance & BALANCE_MASK) | ((integral << 96) & ACCOUNT_INTEGRAL_MASK)
                | ((toPendingRewards << 192) & ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// 5. Update the vault integral with the pending rewards not yet distributed.
        if (!PRE_CHECKPOINT_REWARDS && pendingRewards > 0) {
            integral += uint128(pendingRewards * 1e18 / supply);
        }

        // Update vault storage
        _vault.slot1 = (supply & SUPPLY_MASK) | ((integral << 128) & INTEGRAL_MASK);
    }

    function totalSupply(address vault) external view returns (uint256) {
        return uint128(vaults[vault].slot1 & SUPPLY_MASK);
    }

    function balanceOf(address vault, address account) external view returns (uint256) {
        return uint96(accounts[vault][account].slot & BALANCE_MASK);
    }
}
