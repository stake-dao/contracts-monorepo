/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "src/interfaces/IRegistry.sol";
import "src/interfaces/IStrategy.sol";
import "src/interfaces/IAllocator.sol";
import "src/interfaces/IAccountant.sol";
import "src/interfaces/IERC4626Minimal.sol";

/// @title CoreVault - Base Vault Implementation
/// @notice A minimal ERC4626-compatible vault that delegates accounting to an external Accountant contract
/// @dev Implements core vault functionality with:
///      - ERC4626 minimal interface for deposits and withdrawals
///      - Integration with Registry for contract addresses
///      - Delegation of accounting to Accountant contract
///      - Strategy integration for yield generation
contract CoreVault is ERC20, IERC4626Minimal {
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice The error thrown when a transfer is made to the vault.
    error TransferToVault();

    /// @notice The error thrown when a transfer is made to the zero address.
    error TransferToZeroAddress();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLE STORAGE ACCESS
    //////////////////////////////////////////////////////

    /// @notice Returns the registry contract address from clone args
    /// @return The IRegistry interface of the registry contract
    function REGISTRY() public view returns (IRegistry) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address registry;
        assembly {
            registry := mload(add(args, 20))
        }
        return IRegistry(registry);
    }

    /// @notice Returns the accountant contract address from clone args
    /// @return The IAccountant interface of the accountant contract
    function ACCOUNTANT() public view returns (IAccountant) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address accountant;
        assembly {
            accountant := mload(add(args, 40))
        }
        return IAccountant(accountant);
    }

    /// @notice Returns the underlying asset address from clone args
    /// @return The address of the underlying asset token
    function ASSET() public view returns (address) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address token;
        assembly {
            token := mload(add(args, 60))
        }
        return token;
    }

    /// @notice Returns the allocator contract from registry
    /// @return The IAllocator interface of the allocator contract
    function ALLOCATOR() public view returns (IAllocator) {
        return IAllocator(REGISTRY().ALLOCATOR());
    }

    /// @notice Returns the strategy contract from registry
    /// @return The IStrategy interface of the strategy contract
    function STRATEGY() public view returns (IStrategy) {
        return IStrategy(REGISTRY().STRATEGY());
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor() ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault")) {}

    //////////////////////////////////////////////////////
    /// --- ERC4626 VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @inheritdoc IERC4626Minimal
    function asset() public view returns (address) {
        return ASSET();
    }

    /// @inheritdoc IERC4626Minimal
    function totalAssets() public view returns (uint256) {
        return totalSupply();
    }

    /// @inheritdoc IERC4626Minimal
    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @inheritdoc IERC4626Minimal
    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @inheritdoc IERC4626Minimal
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC4626Minimal
    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC4626Minimal
    function maxWithdraw(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @inheritdoc IERC4626Minimal
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @inheritdoc IERC4626Minimal
    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626Minimal
    function previewMint(uint256 shares) public pure returns (uint256) {
        return convertToAssets(shares);
    }

    /// @inheritdoc IERC4626Minimal
    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626Minimal
    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return convertToAssets(shares);
    }

    //////////////////////////////////////////////////////
    /// --- ERC4626 MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @inheritdoc IERC4626Minimal
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /// @inheritdoc IERC4626Minimal
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    /// @inheritdoc IERC4626Minimal
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner, msg.sender, allowed - shares);
            }
        }
        shares = previewWithdraw(assets);
        _withdraw(owner, receiver, assets, shares);
        return shares;
    }

    /// @inheritdoc IERC4626Minimal
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner, msg.sender, allowed - shares);
            }
        }
        assets = previewRedeem(shares);
        _withdraw(owner, receiver, assets, shares);
        return assets;
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL VAULT OPERATIONS
    //////////////////////////////////////////////////////

    /// @dev Internal function to deposit assets into the vault.
    /// @param account The account providing the assets
    /// @param receiver The account receiving the shares
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares to mint
    function _deposit(address account, address receiver, uint256 assets, uint256 shares) internal virtual {
        /// @dev Call the before deposit hook.
        _beforeDeposit(account, receiver);

        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR().getDepositAllocation(asset(), assets);

        /// 2. Transfer the assets to the strategy from the account.
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(asset()), account, allocation.targets[i], allocation.amounts[i]);
        }

        /// 3. Deposit the assets into the strategy.
        uint256 pendingRewards = STRATEGY().deposit(allocation);

        /// 4. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT().checkpoint(allocation.gauge, address(0), receiver, assets, pendingRewards, allocation.claimRewards);

        /// 5. Mint shares to receiver
        _mint(receiver, shares);
    }

    /// @dev Internal function to withdraw assets from the vault.
    /// @param owner The account that owns the shares
    /// @param receiver The account receiving the assets
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    function _withdraw(address owner, address receiver, uint256 assets, uint256 shares) internal virtual {
        /// @dev Call the before withdraw hook.
        _beforeWithdraw(owner);

        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR().getWithdrawAllocation(asset(), assets);

        /// 2. Withdraw the assets from the strategy.
        uint256 pendingRewards = STRATEGY().withdraw(allocation);

        /// 3. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT().checkpoint(allocation.gauge, owner, address(0), assets, pendingRewards, allocation.claimRewards);

        /// 4. Transfer the assets to the receiver.
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        /// 5. Burn shares from owner
        _burn(owner, shares);
    }

    //////////////////////////////////////////////////////
    /// --- ERC20 OVERRIDES
    //////////////////////////////////////////////////////

    /// @notice Returns the name of the vault token
    /// @return The name string including the underlying asset name
    function name() public view override(ERC20) returns (string memory) {
        return string.concat("StakeDAO ", IERC20Metadata(ASSET()).name(), " Vault");
    }

    /// @notice Returns the symbol of the vault token
    /// @return The symbol string including the underlying asset symbol
    function symbol() public view override(ERC20) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(ASSET()).symbol(), "-vault");
    }

    /// @notice Returns the number of decimals of the vault token
    /// @return The number of decimals matching the underlying asset
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(ASSET()).decimals();
    }

    /// @notice Returns the total supply of vault shares
    /// @return The total supply from the accountant
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT().totalSupply(address(this));
    }

    /// @notice Returns the balance of vault shares for an account
    /// @param account The account to check the balance for
    /// @return The balance from the accountant
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT().balanceOf(address(this), account);
    }

    //////////////////////////////////////////////////////
    /// --- HOOKS
    //////////////////////////////////////////////////////

    /// @notice Hook called before withdrawals
    /// @param account The account withdrawing assets
    function _beforeWithdraw(address account) internal virtual {}

    /// @notice Hook called before deposits
    /// @param account The account depositing assets
    /// @param receiver The account receiving shares
    function _beforeDeposit(address account, address receiver) internal virtual {}
}
