// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";

/// @title RouterModuleWithdraw
/// @notice An upgradeable module that allows for the withdrawal of assets from a given reward vault
contract RouterModuleWithdraw is IRouterModule {
    string public constant name = type(RouterModuleWithdraw).name;
    string public constant version = "1.0.0";

    /// @notice Withdraws `assets` from the vault to `receiver` by burning shares from `owner`.
    /// @dev `owner` must allow the `rewardVault` to spend the `assets`
    /// @param rewardVault The address of the reward vault to call
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to receive the assets. If the receiver is the zero address, the assets will be sent to the owner.
    /// @param owner The address to burn shares from.
    /// @return _ The amount of assets withdrawn.
    /// @custom:throws NotApproved if the Router is not allowed to withdraw the assets
    function withdraw(address rewardVault, uint256 assets, address receiver, address owner)
        external
        returns (uint256)
    {
        return IERC4626(rewardVault).withdraw(assets, receiver, owner);
    }
}
