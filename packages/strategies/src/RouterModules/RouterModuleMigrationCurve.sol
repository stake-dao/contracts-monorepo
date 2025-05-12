// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RouterModuleMigrationCurve is IRouterModule {
    using SafeERC20 for ILiquidityGauge;

    string public constant name = type(RouterModuleMigrationCurve).name;
    string public constant version = "1.0.0";

    error VaultNotCompatible();

    /// @notice Migrates shares from a liquidity gauge to a reward vault
    /// @dev The account must have approved the token to the router contract
    /// @param from The address of the old vault
    /// @param to The address of the new reward vault
    /// @param shares The number of shares to migrate
    function migrate(address from, address to, uint256 shares) external {
        address asset = RewardVault(to).asset();
        require(ILiquidityGauge(from).lp_token() == asset, VaultNotCompatible());

        // 1. Transfer the token of the user to the router contract
        ILiquidityGauge(from).safeTransferFrom(msg.sender, address(this), shares);

        // 2. Withdraw the tokens in the old vault
        ILiquidityGauge(from).withdraw(shares);

        // 3. Deposit the tokens in the reward vault
        ILiquidityGauge(asset).safeIncreaseAllowance(to, shares);
        RewardVault(to).deposit(shares, msg.sender);
    }
}
