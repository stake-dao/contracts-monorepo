// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IRewardReceiver} from "src/interfaces/IRewardReceiver.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ImmutableArgsParser} from "src/libraries/ImmutableArgsParser.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RewardReceiver - Reward Distribution Intermediary
/// @notice A contract that receives rewards from gauges and forwards them to a reward vault.
/// @dev Implements a minimal proxy pattern because each reward vault is associated with its reward receiver.
///      Key responsibilities:
///      - Receives extra reward tokens from gauges.
///      - Forwards rewards to reward vault.
///      - Validates reward tokens against the vault's accepted tokens.
contract RewardReceiver is IRewardReceiver {
    using ImmutableArgsParser for address;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Throws if the reward token is not valid.
    error InvalidToken();

    /// @notice Throws if there are no rewards to distribute.
    error NoRewards();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the reward vault contract.
    /// @return _rewardVault The address of the reward vault contract.
    function rewardVault() public view returns (IRewardVault _rewardVault) {
        return IRewardVault(address(this).readAddress(0));
    }

    //////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Distributes all rewards to the reward vault.
    /// @dev Iterates through all reward tokens registered in the vault,
    ///      checks balances, and forwards any available rewards.
    ///      This function is typically called after a gauge has sent rewards to this contract.
    function distributeRewards() external {
        // Get the list of reward tokens from the reward vault
        address[] memory tokens = rewardVault().getRewardTokens();

        require(tokens.length > 0, NoRewards());

        // Check balances and distribute each reward token
        for (uint256 i; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint128 balance = token.balanceOf(address(this)).toUint128();

            if (balance > 0) _depositRewards(token, balance);
        }
    }

    /// @notice Distributes a specific reward token to the reward vault.
    /// @param token The reward token to distribute.
    /// @dev Validates that the token is accepted by the vault before attempting distribution.
    ///      This function is useful when only a specific reward token needs to be distributed.
    /// @custom:throws InvalidToken If the token is not registered as a valid reward token in the vault.
    function distributeRewardToken(IERC20 token) external {
        // Check if the token is a valid reward token in the vault
        require(rewardVault().isRewardToken(address(token)), InvalidToken());

        // Get the balance of the reward token
        uint128 amount = token.balanceOf(address(this)).toUint128();

        // If there are no rewards to distribute, revert
        require(amount > 0, NoRewards());

        // Deposit the rewards to the vault
        _depositRewards(token, amount);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Deposit rewards to the reward vault.
    /// @param token The reward token to deposit.
    /// @param amount The amount of rewards to deposit.
    function _depositRewards(IERC20 token, uint128 amount) internal {
        /// Check if there's a distribution period in progress.
        if (rewardVault().getPeriodFinish(address(token)) > block.timestamp) return;
        /// Check if the reward receiver is a valid rewards distributor for the reward token.
        if (rewardVault().getRewardsDistributor(address(token)) != address(this)) return;

        /// Approve the reward vault to spend the reward token.
        token.safeIncreaseAllowance(address(rewardVault()), amount);

        // Deposit rewards to the vault
        rewardVault().depositRewards(address(token), amount);
    }
}
