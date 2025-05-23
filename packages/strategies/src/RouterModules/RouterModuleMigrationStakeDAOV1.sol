// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";

interface IVault {
    function token() external view returns (address);
    function withdraw(uint256 shares) external;
    function liquidityGauge() external view returns (address);
}

contract RouterModuleMigrationStakeDAOV1 is IRouterModule {
    using SafeERC20 for IERC20;

    string public constant name = type(RouterModuleMigrationStakeDAOV1).name;
    string public constant version = "1.0.0";

    error VaultNotCompatible();

    /// @notice Migrates shares from a liquidity gauge to a reward vault
    /// @dev The account must have approved the token to the router contract
    /// @param from The address of the old vault
    /// @param to The address of the new reward vault
    /// @param shares The number of shares to migrate
    function migrate(address from, address to, uint256 shares) external {
        address asset = IERC4626(to).asset();
        require(IVault(from).token() == asset, VaultNotCompatible());

        // 1. Transfer user's gauge token to the router contract
        IERC20(IVault(from).liquidityGauge()).safeTransferFrom(msg.sender, address(this), shares);

        // 2. Withdraw the shares from the old vault
        IVault(from).withdraw(shares);

        // 3. Deposit the shares in the new reward vault
        IERC20(asset).forceApprove(to, shares);
        IERC4626(to).deposit(shares, msg.sender);
    }
}
