// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {StdInvariant} from "forge-std/src/StdInvariant.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";

import {Accountant} from "src/Accountant.sol";
import {RewardVault} from "src/RewardVault.sol";
import {VaultHandler} from "test/invariant/handlers/VaultHandler.sol";

contract VaultInvariantTest is StdInvariant, Test {
    ERC20Mock public token;
    ERC20Mock public rewardToken;

    MockRegistry public registry;
    MockStrategy public strategy;
    MockAllocator public allocator;
    Accountant public accountant;
    RewardVault public vault;
    RewardVault public vaultImplementation;
    VaultHandler public handler;

    // Track historical maximum share value for price check invariant
    uint256 public maxShareValue;

    // Track sum of all deposits and withdrawals
    uint256 public sumDeposits;
    uint256 public sumWithdrawals;

    function setUp() public virtual {
        // Setup basic contracts
        token = new ERC20Mock("ERC20Mock", "MTK", 18);
        rewardToken = new ERC20Mock("ERC20Mock", "RTK", 18);

        strategy = new MockStrategy();
        registry = new MockRegistry();
        allocator = new MockAllocator();
        accountant = new Accountant(address(this), address(registry), address(rewardToken), bytes4(bytes("fake_id")));

        vaultImplementation = new RewardVault(bytes4(keccak256("Curve")), address(registry), address(accountant));
        vault = RewardVault(
            Clones.cloneDeterministicWithImmutableArgs(
                address(vaultImplementation),
                abi.encodePacked(address(registry), address(accountant), address(token), address(token)),
                ""
            )
        );

        registry.setVault(address(vault));
        registry.setStrategy(address(strategy));
        registry.setAllocator(address(allocator));

        // Initialize max share value
        maxShareValue = vault.convertToAssets(1e18);

        // Setup handler
        handler = new VaultHandler(token, vault);

        // Configure invariant test settings
        targetContract(address(handler));
        targetSender(address(this));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.transfer.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalAssetsMatchAccounting() public view {
        // Vault's total assets should match the sum of:
        // 1. Tokens in the vault
        // 2. Tokens in the strategy (if any)
        uint256 vaultBalance = token.balanceOf(address(vault));
        uint256 strategyBalance = token.balanceOf(address(strategy));

        assertEq(vault.totalAssets(), vaultBalance + strategyBalance, "Total assets must match actual token balances");
    }

    function invariant_shareValueNeverDecreases() public {
        // Calculate current share value
        uint256 currentShareValue = vault.convertToAssets(1e18);

        // Share value should never decrease
        assertGe(currentShareValue, maxShareValue, "Share value cannot decrease");

        // Update max share value if it increased
        if (currentShareValue > maxShareValue) {
            maxShareValue = currentShareValue;
        }
    }

    function invariant_totalSharesMatchUserBalances() public view {
        // Total supply should match the sum of all holder balances
        uint256 totalSupply = vault.totalSupply();
        uint256 accountantTotalSupply = accountant.totalSupply(address(vault));

        assertEq(totalSupply, accountantTotalSupply, "Total supply must match sum of all balances");

        // Verify sum of all user balances matches total supply
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            sumBalances += vault.balanceOf(handler.users(i));
        }
        assertEq(totalSupply, sumBalances, "Sum of user balances must match total supply");
    }

    function invariant_mathInvariants() public view {
        // Basic sanity checks for the vault's math
        if (vault.totalSupply() > 0) {
            // If there are shares, assets should be non-zero
            assertTrue(vault.totalAssets() > 0, "Non-zero shares must have non-zero assets");

            // Share price should never be zero
            assertTrue(vault.convertToAssets(1e18) > 0, "Share price cannot be zero");
        }

        if (vault.totalAssets() == 0) {
            // If no assets, there should be no shares
            assertEq(vault.totalSupply(), 0, "Zero assets must mean zero shares");
        }
    }

    function invariant_conversionConsistency() public view {
        // Test consistency of conversion functions
        uint256 assets = 1e18;
        uint256 shares = vault.convertToShares(assets);

        // Converting back and forth should not lose value
        assertEq(vault.convertToAssets(shares), assets, "Asset/share conversion must be consistent");
    }

    function invariant_accountantStateConsistency() public view {
        // Check total supply consistency
        assertEq(
            accountant.totalSupply(address(vault)),
            vault.totalSupply(),
            "Accountant total supply must match vault total supply"
        );

        // Check individual balances consistency
        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            address user = handler.users(i);
            assertEq(
                accountant.balanceOf(address(vault), user),
                vault.balanceOf(user),
                "Accountant balance must match vault balance for each user"
            );
        }

        // Check that sum of all balances equals total supply in accountant
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            sumBalances += accountant.balanceOf(address(vault), handler.users(i));
        }
        assertEq(
            sumBalances,
            accountant.totalSupply(address(vault)),
            "Sum of accountant balances must match accountant total supply"
        );

        // Verify no "dust" is left in the accountant
        assertEq(accountant.totalSupply(address(vault)), vault.totalSupply(), "No dust should be left in accountant");
    }
}
