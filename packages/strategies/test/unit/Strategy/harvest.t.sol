// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";

contract Strategy__harvest is StrategyBaseTest {
    function test_RevertsIfNotCalledByAccountant() public {
        vm.prank(makeAddr("not_accountant"));

        vm.expectRevert(abi.encodeWithSignature("OnlyAccountant()"));
        strategy.harvest(gauge, "");
    }

    function test_harvestFromLocker() public {
        /// Set the locker amount
        strategy._cheat_setLockerHarvestAmount(100);

        /// Assert the flush amount is 0
        assertEq(strategy.exposed_getFlushAmount(), 0);

        vm.prank(accountant);
        Strategy.PendingRewards memory pendingRewards = strategy.harvest(gauge, "");

        /// 1. It correctly calls the _harvest function
        /// Since flushAmount is set in the _harvest function
        assertEq(strategy.exposed_getFlushAmount(), 100);
        /// 2. It correctly updates the feeSubjectAmount
        assertEq(pendingRewards.feeSubjectAmount, 100);
        /// 3. It correctly updates the totalAmount
        assertEq(pendingRewards.totalAmount, 100);

        assertEq(rewardToken.balanceOf(address(locker)), 100);
        assertEq(rewardToken.balanceOf(address(sidecar1)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar2)), 0);

        /// 4. Since flush has not been called, and sidecars have no rewards, the accountant has no rewards.
        assertEq(rewardToken.balanceOf(address(accountant)), 0);
    }

    function test_harvestFromSidecars() public {
        /// Assert the flush amount is 0
        assertEq(strategy.exposed_getFlushAmount(), 0);

        /// Cheat the sidecar balances
        rewardToken.mint(sidecar1, 100);
        rewardToken.mint(sidecar2, 100);

        assertEq(ISidecar(sidecar1).getPendingRewards(), 100);
        assertEq(ISidecar(sidecar2).getPendingRewards(), 100);

        vm.prank(accountant);
        Strategy.PendingRewards memory pendingRewards = strategy.harvest(gauge, "");

        /// 1. It correctly calls the _harvest function
        /// Since flushAmount is set in the _harvest function
        assertEq(strategy.exposed_getFlushAmount(), 0);
        /// 2. It correctly updates the feeSubjectAmount
        /// No fees are taken from sidecars rewards
        assertEq(pendingRewards.feeSubjectAmount, 0);
        /// 3. It correctly updates the totalAmount
        assertEq(pendingRewards.totalAmount, 200);

        assertEq(rewardToken.balanceOf(address(locker)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar1)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar2)), 0);
        /// 4. Sidecars send rewards to the accountant directly.
        assertEq(rewardToken.balanceOf(address(accountant)), 200);
    }

    function test_harvestFromSidecarsWithFlush() public {
        /// Assert the flush amount is 0
        assertEq(strategy.exposed_getFlushAmount(), 0);

        /// Cheat the sidecar balances
        rewardToken.mint(sidecar1, 100);
        rewardToken.mint(sidecar2, 100);

        /// Cheat the flush amount
        strategy._cheat_setLockerHarvestAmount(100);

        assertEq(ISidecar(sidecar1).getPendingRewards(), 100);
        assertEq(ISidecar(sidecar2).getPendingRewards(), 100);

        vm.prank(accountant);
        Strategy.PendingRewards memory pendingRewards = strategy.harvest(gauge, "");

        /// 1. It correctly calls the _harvest function
        /// Since flushAmount is set in the _harvest function
        assertEq(strategy.exposed_getFlushAmount(), 100);
        /// 2. It correctly updates the feeSubjectAmount
        /// No fees are taken from sidecars rewards
        assertEq(pendingRewards.feeSubjectAmount, 100);
        /// 3. It correctly updates the totalAmount
        assertEq(pendingRewards.totalAmount, 300);

        assertEq(rewardToken.balanceOf(address(locker)), 100);
        assertEq(rewardToken.balanceOf(address(sidecar1)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar2)), 0);
        /// 4. Sidecars send rewards to the accountant directly.
        assertEq(rewardToken.balanceOf(address(accountant)), 200);

        /// Call flush
        vm.prank(accountant);
        strategy.flush();

        assertEq(rewardToken.balanceOf(address(locker)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar1)), 0);
        assertEq(rewardToken.balanceOf(address(sidecar2)), 0);

        /// Assert the flush amount is 0
        assertEq(strategy.exposed_getFlushAmount(), 0);
        assertEq(rewardToken.balanceOf(address(accountant)), 300);
    }

    function test_harvestWithZeroRewards() public {
        vm.prank(accountant);
        Strategy.PendingRewards memory pendingRewards = strategy.harvest(gauge, "");

        assertEq(pendingRewards.feeSubjectAmount, 0);
        assertEq(pendingRewards.totalAmount, 0);
        assertEq(strategy.exposed_getFlushAmount(), 0);
    }
}
