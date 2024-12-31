/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "src/interfaces/IStrategy.sol";
import "src/interfaces/IAccountant.sol";
import "src/interfaces/IRewardDistributor.sol";

contract Vault is ERC4626 {
    /// @notice Soft checkpoint flag.
    bool immutable SOFT_CHECKPOINT;

    /// @notice The strategy hold the logic associated to deposits and withdrawals.
    IStrategy public immutable STRATEGY;

    /// @notice The allocator, distributing the vault's balance to the gauges.
    IAllocator public immutable ALLOCATOR;

    /// @notice The accountant, maintaining the vault's balance and distribution of main reward token.
    IAccountant public immutable ACCOUNTANT;

    /// @notice The extra-reward token distributor associated with the vault.
    IRewardDistributor public immutable REWARD_DISTRIBUTOR;

    constructor(
        address asset,
        address rewardDistributor,
        address accountant,
        address allocator,
        address strategy,
        bool softCheckpoint
    )
        ERC4626(IERC20(asset))
        ERC20(
            string.concat("StakeDAO ", IERC20Metadata(asset).symbol(), " Vault"),
            string.concat("sd-", IERC20Metadata(asset).symbol(), "-vault")
        )
    {
        STRATEGY = IStrategy(strategy);
        SOFT_CHECKPOINT = softCheckpoint;
        ALLOCATOR = IAllocator(allocator);
        ACCOUNTANT = IAccountant(accountant);
        REWARD_DISTRIBUTOR = IRewardDistributor(rewardDistributor);
    }

    /// @dev Internal function to deposit assets into the vault.
    function _deposit(address caller, address receiver, uint256 assets, uint256) internal override {
        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR.getDepositAllocations(asset(), assets);

        /// 2. Transfer the assets to the strategy from the caller.
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(asset()), caller, allocation.targets[i], allocation.amounts[i]);
        }

        /// 3. Deposit the assets into the strategy.
        uint256 pendingRewards = STRATEGY.deposit(allocation);

        /// 4. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT.checkpoint(allocation.gauge, address(0), receiver, assets, SOFT_CHECKPOINT, pendingRewards);

        /// 5. Emit the deposit event.
        emit Deposit(caller, receiver, assets, assets);
    }

    /// @dev Internal function to withdraw assets from the vault.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR.getWithdrawAllocations(asset(), assets);

        /// 2. Withdraw the assets from the strategy.
        uint256 pendingRewards = STRATEGY.withdraw(allocation);

        /// 3. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT.checkpoint(allocation.gauge, owner, address(0), assets, SOFT_CHECKPOINT, pendingRewards);

        /// 4. Transfer the assets to the receiver.
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        /// 5. Emit the withdraw event.
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    //////////////////////////////////////////////////////
    /// --- HOOKS
    //////////////////////////////////////////////////////

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        REWARD_DISTRIBUTOR.updateReward(to);
        REWARD_DISTRIBUTOR.updateReward(from);
    }
}
