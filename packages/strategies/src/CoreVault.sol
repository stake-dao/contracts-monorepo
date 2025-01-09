/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "@solady/src/utils/LibClone.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "src/interfaces/IStrategy.sol";
import "src/interfaces/IAllocator.sol";
import "src/interfaces/IAccountant.sol";

contract CoreVault is ERC4626 {
    function STRATEGY() public view returns (IStrategy) {
        return IStrategy(address(bytes20(LibClone.argsOnClone(address(this), 0, 20))));
    }

    function ALLOCATOR() public view returns (IAllocator) {
        return IAllocator(address(bytes20(LibClone.argsOnClone(address(this), 20, 40))));
    }

    function ACCOUNTANT() public view returns (IAccountant) {
        return IAccountant(address(bytes20(LibClone.argsOnClone(address(this), 40, 60))));
    }

    function ASSET() public view returns (address) {
        return address(bytes20(LibClone.argsOnClone(address(this), 60, 80)));
    }

    /// @notice The error thrown when a transfer is made to the vault.
    error TransferToVault();

    /// @notice The error thrown when a transfer is made to the zero address.
    error TransferToZeroAddress();

    constructor() ERC4626(IERC20(address(0))) ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault")) {}

    /// @dev Internal function to deposit assets into the vault.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        /// @dev Call the before deposit hook.
        _beforeDeposit(caller, receiver, assets, shares);

        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR().getDepositAllocation(asset(), assets);

        /// 2. Transfer the assets to the strategy from the caller.
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(asset()), caller, allocation.targets[i], allocation.amounts[i]);
        }

        /// 3. Deposit the assets into the strategy.
        uint256 pendingRewards = STRATEGY().deposit(allocation);

        /// 4. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT().checkpoint(allocation.gauge, address(0), receiver, assets, pendingRewards);

        /// 5. Emit the deposit event.
        emit Deposit(caller, receiver, assets, shares);
    }

    /// @dev Internal function to withdraw assets from the vault.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        /// @dev Call the before withdraw hook.
        _beforeWithdraw(caller, receiver, owner, assets, shares);

        /// 1. Get the allocation.
        IAllocator.Allocation memory allocation = ALLOCATOR().getWithdrawAllocation(asset(), assets);

        /// 2. Withdraw the assets from the strategy.
        uint256 pendingRewards = STRATEGY().withdraw(allocation);

        /// 3. Checkpoint the vault. The accountant will deal with minting and burning.
        ACCOUNTANT().checkpoint(allocation.gauge, owner, address(0), assets, pendingRewards);

        /// 4. Transfer the assets to the receiver.
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        /// 5. Emit the withdraw event.
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    //////////////////////////////////////////////////////
    /// --- ERC4626 OVERRIDES
    //////////////////////////////////////////////////////

    function asset() public view override returns (address) {
        return ASSET();
    }

    function totalAssets() public view virtual override returns (uint256) {
        return totalSupply();
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return assets;
    }

    //////////////////////////////////////////////////////
    /// --- ERC20 OVERRIDES
    //////////////////////////////////////////////////////

    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("StakeDAO ", IERC20Metadata(ASSET()).name(), " Vault");
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(ASSET()).symbol(), "-vault");
    }

    function decimals() public view override(ERC4626) returns (uint8) {
        return IERC20Metadata(ASSET()).decimals();
    }

    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT().totalSupply(address(this));
    }

    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT().balanceOf(address(this), account);
    }

    function _beforeDeposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {}

    function _beforeWithdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
    {}
}
