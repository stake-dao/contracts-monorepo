// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {RewardVault} from "src/RewardVault.sol";

interface IVault {
    function token() external view returns (address);
    function withdraw(uint256 shares) external;
    function transferFrom(address from, address to, uint256 shares) external;
    function liquidityGauge() external view returns (address);
}

contract RouterModuleMigrationStakeDAOV1 is IRouterModule {
    string public constant name = type(RouterModuleMigrationStakeDAOV1).name;
    string public constant version = "1.0.0";

    error VaultNotCompatible();

    /// @notice Migrates shares from a liquidity gauge to a reward vault
    /// @dev The account must have approved the token to the router contract
    /// @param from The address of the old vault
    /// @param to The address of the new reward vault
    /// @param account The address of the account to migrate
    /// @param shares The number of shares to migrate
    function migrate(address from, address to, address account, uint256 shares) external {
        address asset = RewardVault(to).asset();
        require(IVault(from).token() == asset, VaultNotCompatible());

        // 1. Transfer user's gauge token to the router contract
        IERC20(IVault(from).liquidityGauge()).transferFrom(account, address(this), shares);

        // 2. Withdraw the shares from the old vault
        IVault(from).withdraw(shares);

        // 3. Deposit the shares in the new reward vault
        IERC20(asset).approve(to, shares);
        RewardVault(to).deposit(shares, account);
    }
}
