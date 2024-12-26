/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/interfaces/IRegistry.sol";

contract Accountant {
    struct Vault {
        uint128 supply;
        uint128 integral;
    }

    struct Account {
        uint96 balance;
        uint96 integral;
        uint64 pendingRewards;
    }

    /// @notice Whether the vault integral is updated before the accounts checkpoint.
    bool public immutable updateBeforeCheckpoint;

    /// @notice The registry of vaults.
    address public immutable registry;

    /// @notice The reward token.
    address public immutable rewardToken;

    /// @notice Supply of vaults.
    /// @dev Vault address -> Vault.
    mapping(address => Vault) public vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> Account.
    mapping(address => mapping(address => Account)) public accounts;

    error OnlyVault();

    constructor(address _registry, address _rewardToken, bool _updateBeforeCheckpoint) {
        registry = _registry;
        rewardToken = _rewardToken;
        updateBeforeCheckpoint = _updateBeforeCheckpoint;
    }

    /// @notice Function called by vaults to checkpoint the state of the vault on every account action.
    /// @param vault The vault address.
    /// @param from The address of the sender.
    /// @param to The address of the receiver.
    /// @param amount The amount of tokens transferred.
    /// @param pendingRewards The amount of pending rewards.
    function checkpoint(address vault, address from, address to, uint256 amount, uint256 pendingRewards) external {
        if (msg.sender != IRegistry(registry).vaults(msg.sender)) revert OnlyVault();

        Vault storage _vault = vaults[vault];

        // If configured, update the vault's integral with new rewards before processing transfers
        if (updateBeforeCheckpoint) {
            _vault.integral += uint128(pendingRewards * 1e18 / _vault.supply);
        }

        // Handle minting - increase total supply when tokens are minted
        if (from == address(0)) {
            _vault.supply += uint128(amount);
        }
        // Handle outgoing transfer - update sender's rewards and decrease their balance
        else {
            Account storage _from = accounts[vault][from];
            _from.pendingRewards += uint64((_vault.integral - _from.integral) * _from.balance / _vault.supply);
            _from.balance -= uint96(amount);
        }

        // Handle burning - decrease total supply when tokens are burned
        if (to == address(0)) {
            _vault.supply -= uint128(amount);
        }
        // Handle incoming transfer - update receiver's rewards and increase their balance
        else {
            Account storage _to = accounts[vault][to];
            _to.pendingRewards += uint64((_vault.integral - _to.integral) * _to.balance / _vault.supply);
            _to.balance += uint96(amount);
        }

        // If configured, update the vault's integral with new rewards after processing transfers
        if (!updateBeforeCheckpoint) {
            _vault.integral += uint128(pendingRewards * 1e18 / _vault.supply);
        }
    }
}
