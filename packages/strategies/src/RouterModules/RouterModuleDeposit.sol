// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";

/// @title RouterModuleDeposit
/// @notice An upgradeable module that allows for the deposit of assets into a given reward vault
contract RouterModuleDeposit is IRouterModule {
    string public constant name = type(RouterModuleDeposit).name;
    string public constant version = "1.0.0";

    /// @notice Deposit assets into the reward vault
    /// @param rewardVault The address of the reward vault to call
    /// @param assets The amount of assets to deposit
    /// @custom:throws ZeroAddress if the account is the zero address
    /// @custom:throws SafeERC20FailedOperation if the account does not have enough allowance
    ///                for the reward vault to transfer the assets
    function deposit(address rewardVault, address receiver, uint256 assets) public returns (uint256) {
        return IRewardVault(rewardVault).deposit(msg.sender, receiver, assets, address(0));
    }

    /// @notice Deposit assets into the reward vault
    /// @param rewardVault The address of the reward vault to call
    /// @param assets The amount of assets to deposit
    /// @param referrer The address of the referrer
    /// @custom:throws ZeroAddress if the account is the zero address
    /// @custom:throws SafeERC20FailedOperation if the account does not have enough allowance
    ///                for the reward vault to transfer the assets
    function deposit(address rewardVault, address receiver, uint256 assets, address referrer)
        public
        returns (uint256)
    {
        return IRewardVault(rewardVault).deposit(msg.sender, receiver, assets, referrer);
    }
}
