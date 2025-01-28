// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";

import {Accountant} from "src/Accountant.sol";
import {RewardVault, LibClone} from "src/RewardVault.sol";

contract Vault is Test {
    MockToken public token;
    MockRegistry public registry;
    MockStrategy public strategy;
    MockAllocator public allocator;

    Accountant public accountant;

    RewardVault public vault;
    RewardVault public vaultImplementation;

    uint256 public constant AMOUNT = 10_000_000 ether;

    function setUp() public virtual {
        token = new MockToken("MockToken", "MTK", 18);
        token.mint(address(this), AMOUNT);

        strategy = new MockStrategy();
        registry = new MockRegistry();
        allocator = new MockAllocator();
        accountant = new Accountant(address(registry), address(token));

        vaultImplementation = new RewardVault();
        vault = RewardVault(
            LibClone.clone(
                address(vaultImplementation), abi.encodePacked(address(registry), address(accountant), address(token))
            )
        );

        registry.setVault(address(vault));
        registry.setStrategy(address(strategy));
        registry.setAllocator(address(allocator));
    }

    function test_setup() public virtual {
        assertEq(address(vault.REGISTRY()), address(registry));
        assertEq(address(vault.STRATEGY()), address(strategy));
        assertEq(address(vault.ALLOCATOR()), address(allocator));
        assertEq(address(vault.ACCOUNTANT()), address(accountant));
        assertEq(address(vault.ASSET()), address(token));

        assertEq(vault.name(), "StakeDAO MockToken Vault");
        assertEq(vault.symbol(), "sd-MTK-vault");
        assertEq(vault.decimals(), 18);
    }

    function test_deposit() public virtual {
        token.approve(address(vault), type(uint256).max);
        vault.deposit(AMOUNT, address(this));

        assertEq(token.balanceOf(address(vault)), AMOUNT);
        assertEq(token.balanceOf(address(this)), 0);

        assertEq(vault.totalSupply(), AMOUNT);
        assertEq(vault.totalAssets(), AMOUNT);
        assertEq(vault.balanceOf(address(this)), AMOUNT);

        assertEq(accountant.totalSupply(address(vault)), AMOUNT);
        assertEq(accountant.balanceOf(address(vault), address(this)), AMOUNT);
    }

    function test_withdraw() public virtual {
        token.approve(address(vault), type(uint256).max);
        vault.deposit(AMOUNT, address(this));

        vault.withdraw(AMOUNT - 100 ether, address(this), address(this));

        assertEq(token.balanceOf(address(vault)), 100 ether);
        assertEq(token.balanceOf(address(this)), AMOUNT - 100 ether);

        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);
        assertEq(vault.balanceOf(address(this)), 100 ether);

        assertEq(accountant.totalSupply(address(vault)), 100 ether);
        assertEq(accountant.balanceOf(address(vault), address(this)), 100 ether);
    }
}
