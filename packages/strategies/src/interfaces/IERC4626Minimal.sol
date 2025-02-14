// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IERC4626Minimal
/// @notice Minimal interface for ERC4626 vaults
interface IERC4626Minimal is IERC20 {
    /// @notice The address of the underlying token used for the Vault
    function asset() external view returns (address);

    /// @notice Total amount of the underlying asset managed by vault
    function totalAssets() external view returns (uint256);

    /// @notice The amount of shares that would be exchanged for assets
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice The amount of assets that would be exchanged for shares
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Deposit assets and receive shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mint shares by depositing assets
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Redeem shares for assets
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Preview deposit
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Preview mint
    function previewMint(uint256 shares) external view returns (uint256);

    /// @notice Preview withdraw
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Preview redeem
    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Maximum amount of assets that can be deposited
    function maxDeposit(address) external view returns (uint256);

    /// @notice Maximum amount of shares that can be minted
    function maxMint(address) external view returns (uint256);

    /// @notice Maximum amount of assets that can be withdrawn
    function maxWithdraw(address owner) external view returns (uint256);

    /// @notice Maximum amount of shares that can be redeemed
    function maxRedeem(address owner) external view returns (uint256);
}
