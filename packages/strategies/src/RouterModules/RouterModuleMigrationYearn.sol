// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RouterModuleMigrationYearn is IRouterModule {
    string public constant name = type(RouterModuleMigrationYearn).name;
    string public constant version = "1.0.0";

    error VaultNotCompatible();

    /// @notice Migrates shares from convex to a reward vault
    /// @dev The account must have approved the token to the router contract
    /// @param from The address of the old vault
    /// @param to The address of the new reward vault
    /// @param account The address of the account to migrate
    /// @param shares The number of shares to migrate
    function migrate(address from, address to, address account, uint256 shares) external {
        address asset = RewardVault(to).asset();
        require(YearnVault(from).token() == asset, VaultNotCompatible());

        // 1. Transfer the token of the user to the router contract
        YearnVault(from).transferFrom(account, address(this), shares);

        // 2. Withdraw the tokens in the old vault
        YearnVault(from).withdraw(shares);

        // 3. Deposit the tokens in the reward vault
        IERC20(asset).approve(to, shares);
        RewardVault(to).deposit(shares, account);
    }
}

interface YearnVault {
    function withdraw(uint256 maxShares) external returns (uint256);
    function token() external view returns (address);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
