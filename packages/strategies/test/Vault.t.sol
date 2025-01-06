// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "src/extensions/RewardVault.sol";

contract Vault is Test {
    RewardVault public vault;
    RewardVault public vaultImplementation;

    function setUp() public virtual {
        vaultImplementation = new RewardVault(true);
        vault = RewardVault(
            LibClone.clone(address(vaultImplementation), abi.encodePacked(address(1), address(2), address(3), address(4)))
        );
    }

    function test_setup() public view virtual {
        assertEq(address(vault.STRATEGY()), address(1));
        assertEq(address(vault.ALLOCATOR()), address(2));
        assertEq(address(vault.ACCOUNTANT()), address(3));
        assertEq(address(vault.ASSET()), address(4));
    }
}
