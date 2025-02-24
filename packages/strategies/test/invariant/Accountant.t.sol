// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {StdInvariant} from "forge-std/src/StdInvariant.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";
import {Accountant} from "src/Accountant.sol";

import {RewardVault} from "src/RewardVault.sol";
import {AccountantHandler} from "test/invariant/handlers/AccountantHandler.sol";

contract AccountantInvariantTest is StdInvariant, Test {
    ERC20Mock public token;
    MockRegistry public registry;
    MockStrategy public strategy;
    MockAllocator public allocator;
    Accountant public accountant;
    RewardVault public vault;
    RewardVault public vaultImplementation;
    AccountantHandler public handler;

    function setUp() public virtual {
        // Setup basic contracts
        token = new ERC20Mock("ERC20Mock", "MTK", 18);
        strategy = new MockStrategy();
        registry = new MockRegistry();
        allocator = new MockAllocator();
        accountant = new Accountant(address(this), address(registry), address(token));

        vaultImplementation = new RewardVault(bytes4(keccak256("Curve")));
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

        // Setup handler
        handler = new AccountantHandler(token, accountant, vault);

        // Configure invariant test settings
        targetContract(address(handler));
        targetSender(address(this));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.claim.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyConsistency() public view {
        // Check that total supply matches sum of all user balances
        uint256 totalSupply = accountant.totalSupply(address(vault));
        uint256 sumBalances = 0;

        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            sumBalances += accountant.balanceOf(address(vault), handler.users(i));
        }

        assertEq(totalSupply, sumBalances, "Total supply must match sum of all balances");
        assertEq(totalSupply, vault.totalSupply(), "Accountant and vault total supply must match");
    }

    function invariant_nonNegativeBalances() public view {
        // Verify all user balances are non-negative
        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            address user = handler.users(i);
            assertTrue(accountant.balanceOf(address(vault), user) >= 0, "User balances cannot be negative");
        }

        // Verify global supplies are non-negative
        assertTrue(accountant.totalSupply(address(vault)) >= 0, "Total supply cannot be negative");
    }

    function invariant_accountantStateConsistency() public view {
        // Check total supply consistency between vault and accountant
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

        // Verify no "dust" is left in the accountant
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < handler.NUM_USERS(); i++) {
            sumBalances += accountant.balanceOf(address(vault), handler.users(i));
        }
        assertEq(
            sumBalances,
            accountant.totalSupply(address(vault)),
            "Sum of accountant balances must match accountant total supply"
        );
    }
}
