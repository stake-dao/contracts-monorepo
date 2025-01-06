// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";
import {MockAccountant} from "test/mocks/MockAccountant.sol";

import {RewardVault, LibClone} from "src/extensions/RewardVault.sol";

contract Vault is Test {
    MockToken public token;
    MockStrategy public strategy;
    MockAllocator public allocator;
    MockAccountant public accountant;

    RewardVault public vault;
    RewardVault public vaultImplementation;

    function setUp() public virtual {
        token = new MockToken("MockToken", "MTK", 18);
        token.mint(address(this), 10_000_000 ether);

        strategy = new MockStrategy();
        accountant = new MockAccountant();

        vaultImplementation = new RewardVault(true);
        vault = RewardVault(
            LibClone.clone(
                address(vaultImplementation),
                abi.encodePacked(address(strategy), address(allocator), address(accountant), address(token))
            )
        );
    }

    function test_setup() public view virtual {
        assertEq(address(vault.STRATEGY()), address(strategy));
        assertEq(address(vault.ALLOCATOR()), address(allocator));
        assertEq(address(vault.ACCOUNTANT()), address(accountant));
        assertEq(address(vault.ASSET()), address(token));

        assertEq(vault.name(), "StakeDAO MockToken Vault");
        assertEq(vault.symbol(), "sd-MTK-vault");
        assertEq(vault.decimals(), 18);
    }
}
