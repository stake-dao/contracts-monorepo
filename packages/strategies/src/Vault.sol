/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "src/interfaces/IStrategy.sol";
import "src/interfaces/IAccountant.sol";
import "src/interfaces/IRewardDistributor.sol";
import "src/interfaces/IAllocator.sol";

contract Vault is ERC4626 {
    /// @notice The strategy hold the logic associated to deposits and withdrawals.
    IStrategy public immutable STRATEGY;

    /// @notice The allocator, distributing the vault's balance to the gauges.
    IAllocator public immutable ALLOCATOR;

    /// @notice The accountant, maintaining the vault's balance and distribution of main reward token.
    IAccountant public immutable ACCOUNTANT;

    /// @notice The extra-reward token distributor associated with the vault.
    IRewardDistributor public immutable REWARD_DISTRIBUTOR;

    constructor(address asset, address rewardDistributor, address accountant, address allocator, address strategy)
        ERC4626(IERC20(asset))
        ERC20(
            string.concat("StakeDAO ", IERC20Metadata(asset).symbol(), " Vault"),
            string.concat("sd-", IERC20Metadata(asset).symbol(), "-vault")
        )
    {
        STRATEGY = IStrategy(strategy);
        ALLOCATOR = IAllocator(allocator);
        ACCOUNTANT = IAccountant(accountant);
        REWARD_DISTRIBUTOR = IRewardDistributor(rewardDistributor);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        REWARD_DISTRIBUTOR.updateReward(to);
        REWARD_DISTRIBUTOR.updateReward(from);
    }
}