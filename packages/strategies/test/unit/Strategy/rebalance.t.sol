// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/StrategyBaseTest.t.sol";

import {Strategy} from "src/Strategy.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";

contract Strategy__rebalance is StrategyBaseTest {
    function test_Rebalance() public {
        /// Total amount is 600
        /// Current allocation is:
        /// - 100 in locker
        /// - 200 in sidecar1
        /// - 300 in sidecar2

        /// Cheat the sidecar balances
        stakingToken.mint(address(locker), 100);
        stakingToken.mint(address(sidecar1), 200);
        stakingToken.mint(address(sidecar2), 300);

        vm.prank(vault);
        strategy.deposit(allocation, false);

        /// Assert the total balance is 600
        assertEq(strategy.balanceOf(gauge), 600);
        assertEq(stakingToken.balanceOf(address(locker)), 100);
        assertEq(stakingToken.balanceOf(address(sidecar1)), 200);
        assertEq(stakingToken.balanceOf(address(sidecar2)), 300);

        /// We want to rebalance to:
        /// We want to rebalance to:
        /// - 200 in locker
        /// - 400 in sidecar1
        /// - 0 in sidecar2
        uint256[] memory rebalanceAmounts = new uint256[](3);
        rebalanceAmounts[0] = 200;
        rebalanceAmounts[1] = 400;
        rebalanceAmounts[2] = 0;

        /// Set the rebalance amounts
        allocation.amounts = rebalanceAmounts;

        /// Set the rebalanced allocation.
        strategy._cheat_getRebalancedAllocation(gauge, address(allocator), 600, allocation);

        vm.prank(vault);
        strategy.rebalance(gauge);

        assertEq(strategy.balanceOf(gauge), 600);
        assertEq(stakingToken.balanceOf(address(locker)), 200);
        assertEq(stakingToken.balanceOf(address(sidecar1)), 400);
        assertEq(stakingToken.balanceOf(address(sidecar2)), 0);
    }

    function test_RevertNotNeeded() public {
        vm.expectRevert(abi.encodeWithSelector(Strategy.RebalanceNotNeeded.selector));
        strategy.rebalance(gauge);
    }
}
