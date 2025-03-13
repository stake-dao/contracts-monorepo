// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRewardVault} from "src/interfaces/IRewardVault.sol";

/// @title RewardReceiver - Reward Distribution Intermediary
/// @notice A contract that receives rewards from gauges and forwards them to a reward vault.
/// @dev Implements a minimal proxy pattern because each reward vault is associated with its reward receiver.
///      Key responsibilities:
///      - Receives extra reward tokens from gauges.
///      - Forwards rewards to reward vault.
///      - Validates reward tokens against the vault's accepted tokens.
contract RewardReceiver {
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Throws if the reward token is not valid.
    error InvalidToken();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the reward vault contract.
    /// @return _rewardVault The address of the reward vault contract.
    function rewardVault() public view returns (IRewardVault _rewardVault) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _rewardVault := mload(add(args, 20))
        }
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

        // Check balances and distribute each reward token
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance > 0) {
                /// Approve the reward vault to spend the reward token.
                IERC20(token).safeIncreaseAllowance(address(rewardVault()), balance);

                // Deposit rewards to the vault
                // TODO: unsafe: cast the balance to uint128 safely
                IRewardVault(rewardVault()).depositRewards(token, uint128(balance));
            }
        }
    }

    /// @notice Distributes a specific reward token to the reward vault.
    /// @param token The reward token to distribute.
    /// @dev Validates that the token is accepted by the vault before attempting distribution.
    ///      This function is useful when only a specific reward token needs to be distributed.
    /// @custom:throws InvalidToken If the token is not registered as a valid reward token in the vault.
    function distributeRewardToken(IERC20 token) external {
        // Check if the token is a valid reward token in the vault
        if (!rewardVault().isRewardToken(address(token))) revert InvalidToken();

        // Get the balance of the reward token
        uint256 amount = token.balanceOf(address(this));

        if (amount > 0) {
            /// Approve the reward vault to spend the reward token.
            token.safeIncreaseAllowance(address(rewardVault()), amount);

            // Deposit rewards to the vault
            // TODO: unsafe: cast the balance to uint128 safely
            rewardVault().depositRewards(address(token), uint128(amount));
        }
    }
}
