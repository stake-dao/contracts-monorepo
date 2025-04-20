// SPDX-License-Identifier: AGPL-3.0-only
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
    /// @param account The address of the account to deposit for
    /// @param assets The amount of assets to deposit
    /// @custom:throws OnlyAllowed if this function is not called using delegatecall
    ///                from an account authorized by the protocol controller
    /// @custom:throws ZeroAddress if the account is the zero address
    /// @custom:throws SafeERC20FailedOperation if the account does not have enough allowance
    ///                for the reward vault to transfer the assets
    function deposit(address rewardVault, address account, uint256 assets) external returns (uint256) {
        return IRewardVault(rewardVault).deposit(account, assets);
    }

    /// @notice Deposit assets into the reward vault
    /// @param rewardVault The address of the reward vault to call
    /// @param account The address of the account to deposit for
    /// @param assets The amount of assets to deposit
    /// @param referrer The address of the referrer
    /// @custom:throws OnlyAllowed if this function is not called using delegatecall
    ///                from an account authorized by the protocol controller
    /// @custom:throws ZeroAddress if the account is the zero address
    /// @custom:throws SafeERC20FailedOperation if the account does not have enough allowance
    ///                for the reward vault to transfer the assets
    function deposit(address rewardVault, address account, uint256 assets, address referrer)
        public
        payable
        returns (uint256)
    {
        return IRewardVault(rewardVault).deposit(account, assets, referrer);
    }
}
