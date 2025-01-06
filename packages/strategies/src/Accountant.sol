/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/interfaces/IRegistry.sol";

/// @notice The source of truth.
contract Accountant {
    struct Vault {
        uint128 supply;
        uint128 integral;
        uint64 lastUpdateTime;
        uint64 pendingRewards;
    }

    struct Donation {
        address vault;
        uint96 amount;
        uint64 timestamp;
    }

    struct Account {
        uint96 balance;
        uint96 integral;
        uint64 pendingRewards;
    }

    /// @notice The registry of vaults.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice Whether the vault integral is updated before the accounts checkpoint. Careful, as false means vault has been harvested before the accounts checkpoint.
    bool public immutable PRE_CHECKPOINT_REWARDS;

    /// @notice Supply of vaults.
    /// @dev Vault address -> Vault.
    mapping(address => Vault) public vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> Account.
    mapping(address => mapping(address => Account)) public accounts;

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

        Vault storage _vault = vaults[asset];

        /// 0. Update the vault integral with the pending rewards distributed.
        if (PRE_CHECKPOINT_REWARDS && pendingRewards > 0) {
            _vault.integral += uint128(pendingRewards * 1e18 / _vault.supply);
        }

        /// 1. Minting.
        if (from == address(0)) {
            _vault.supply += uint128(amount);
        }
        /// 2. Transferring. Update the "from" account.
        else {
            Account storage _from = accounts[msg.sender][from];
            _from.pendingRewards += uint64((_vault.integral - _from.integral) * _from.balance / _vault.supply);
            _from.balance -= uint96(amount);
        }

        /// 3. Burning.
        if (to == address(0)) {
            _vault.supply -= uint128(amount);
        }
        /// 4. Transferring. Update the "to" account.
        else {
            Account storage _to = accounts[msg.sender][to];
            _to.pendingRewards += uint64((_vault.integral - _to.integral) * _to.balance / _vault.supply);
            _to.balance += uint96(amount);
        }

        /// 5. Update the vault integral with the pending rewards no yet distributed.
        if (!PRE_CHECKPOINT_REWARDS && pendingRewards > 0) {
            _vault.integral += uint128(pendingRewards * 1e18 / _vault.supply);
        }
    }
}
