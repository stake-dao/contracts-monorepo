// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";

/// @title RouterModuleClaim
/// @notice An upgradeable module that allows for the claim of rewards from a given reward vault
contract RouterModuleClaim is IRouterModule {
    string public constant name = type(RouterModuleClaim).name;
    string public constant version = "1.0.0";

    /// @notice Claim rewards from the reward vault
    /// @param rewardVault The address of the reward vault to call
    /// @param account The address of the account to claim for
    /// @param tokens The array of tokens to claim
    /// @param receiver The address to receive the rewards
    /// @custom:throws OnlyAllowed if this function is not called using delegatecall
    ///                from an account authorized by the protocol controller
    function claim(address rewardVault, address account, address[] calldata tokens, address receiver)
        external
        returns (uint256[] memory amounts)
    {
        amounts = IRewardVault(rewardVault).claim(account, tokens, receiver);
    }
}
