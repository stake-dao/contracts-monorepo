// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {MockToken} from "test/mocks/MockToken.sol";
import {Accountant} from "src/Accountant.sol";
import {RewardVault} from "src/RewardVault.sol";

contract AccountantHandler is Test {
    MockToken public token;
    Accountant public accountant;
    RewardVault public vault;
    address[] public users;
    uint256 public constant NUM_USERS = 10;

    // Track user rewards
    mapping(address => uint256) public userRewards;
    uint256 public totalUserRewards;

    // Constants for bounds
    uint256 public constant MAX_DONATION = 1000e18;
    uint256 public constant INITIAL_DEPOSIT = 10000e18;

    constructor(MockToken _token, Accountant _accountant, RewardVault _vault) {
        token = _token;
        accountant = _accountant;
        vault = _vault;

        // Create test users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            token.mint(user, 1000000e18);
            vm.startPrank(user);
            token.approve(address(accountant), type(uint256).max);
            token.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }

        // Setup initial state - users deposit into vault to get shares
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = users[i];
            vm.prank(user);
            vault.deposit(INITIAL_DEPOSIT, user);
        }
    }

    function claim(uint256 userSeed) public {
        address user = users[userSeed % NUM_USERS];

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        uint256 balanceBefore = token.balanceOf(user);

        vm.prank(user);
        try accountant.claim(vaults, user, new bytes[](vaults.length)) {
            uint256 claimed = token.balanceOf(user) - balanceBefore;
            userRewards[user] += claimed;
            totalUserRewards += claimed;
        } catch {
            // If claim fails, no state update needed
        }
    }

    function getExpectedFees(uint256 amount) public view returns (uint256) {
        return (amount * (accountant.getHarvestFeePercent() + accountant.getProtocolFeePercent())) / 1e18;
    }
}
