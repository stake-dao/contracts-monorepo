// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVault} from "src/RewardVault.sol";

contract VaultHandler is Test {
    ERC20Mock public token;
    RewardVault public vault;
    address[] public users;
    uint256 public constant NUM_USERS = 10;

    constructor(ERC20Mock _token, RewardVault _vault) {
        token = _token;
        vault = _vault;

        // Create test users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            token.mint(user, 1000000e18);
            vm.prank(user);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 userSeed, uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(users[userSeed % NUM_USERS]));
        if (amount == 0) return;

        vm.prank(users[userSeed % NUM_USERS]);
        vault.deposit(amount, users[userSeed % NUM_USERS]);
    }

    function withdraw(uint256 userSeed, uint256 amount) public {
        address user = users[userSeed % NUM_USERS];
        amount = bound(amount, 0, vault.balanceOf(user));
        if (amount == 0) return;

        vm.prank(user);
        vault.withdraw(amount, user, user);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = users[fromSeed % NUM_USERS];
        address to = users[toSeed % NUM_USERS];
        if (from == to) return;

        amount = bound(amount, 0, vault.balanceOf(from));
        if (amount == 0) return;

        vm.prank(from);
        vault.transfer(to, amount);
    }
}
