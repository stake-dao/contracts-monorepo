// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RouterModuleMigrationYearn is IRouterModule {
    using SafeERC20 for IYearnVault;

    string public constant name = type(RouterModuleMigrationYearn).name;
    string public constant version = "1.0.0";

    error VaultNotCompatible();

    /// @notice Migrates shares from convex to a reward vault
    /// @dev The account must have approved the token to the router contract
    /// @param from The address of the old vault
    /// @param to The address of the new reward vault
    /// @param shares The number of shares to migrate
    function migrate(address from, address to, uint256 shares) external {
        address asset = RewardVault(to).asset();
        require(IYearnVault(from).token() == asset, VaultNotCompatible());

        // 1. Transfer the token of the user to the router contract
        IYearnVault(from).safeTransferFrom(msg.sender, address(this), shares);

        // 2. Withdraw the tokens in the old vault
        IYearnVault(from).withdraw(shares);

        // 3. Deposit the tokens in the reward vault
        IYearnVault(asset).forceApprove(to, shares);
        RewardVault(to).deposit(shares, msg.sender);
    }
}

interface IYearnVault is IERC20 {
    function withdraw(uint256 maxShares) external returns (uint256);
    function token() external view returns (address);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
