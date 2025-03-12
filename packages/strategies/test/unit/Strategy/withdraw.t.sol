// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/StrategyBaseTest.t.sol";

import {Strategy} from "src/Strategy.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";

contract Strategy__withdraw is StrategyBaseTest {
    function test_RevertCallerNotAllowed() public {
        address notAllowed = makeAddr("notAllowed");

        vm.prank(notAllowed);
        vm.expectRevert(abi.encodeWithSelector(Strategy.OnlyVault.selector));
        strategy.withdraw(allocation);
    }

    function test_RevertGaugeShutdown() public {
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.isShutdown.selector, gauge), abi.encode(true)
        );

        vm.expectRevert(abi.encodeWithSelector(Strategy.GaugeShutdown.selector));
        vm.prank(vault);
        strategy.withdraw(allocation);
    }

    function test_Withdraw() public {
        stakingToken.mint(address(locker), 100);
        stakingToken.mint(address(sidecar1), 200);
        stakingToken.mint(address(sidecar2), 300);

        vm.prank(vault);
        strategy.deposit(allocation);

        assertEq(strategy.balanceOf(gauge), 600);
        assertEq(stakingToken.balanceOf(address(locker)), 100);
        assertEq(stakingToken.balanceOf(address(sidecar1)), 200);
        assertEq(stakingToken.balanceOf(address(sidecar2)), 300);

        strategy._cheat_setSyncRewards(100, 400);

        vm.prank(vault);
        Strategy.PendingRewards memory pendingRewards = strategy.withdraw(allocation);

        assertEq(strategy.balanceOf(gauge), 0);
        assertEq(stakingToken.balanceOf(address(locker)), 0);
        assertEq(stakingToken.balanceOf(address(sidecar1)), 0);
        assertEq(stakingToken.balanceOf(address(sidecar2)), 0);
        assertEq(stakingToken.balanceOf(address(vault)), 600);

        assertEq(pendingRewards.feeSubjectAmount, 100);
        assertEq(pendingRewards.totalAmount, 400);
    }
}
