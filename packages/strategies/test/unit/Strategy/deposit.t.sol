// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract Strategy__deposit is StrategyBaseTest {
    function test_RevertsIfNotCalledByVault() public {
        vm.prank(makeAddr("not_vault"));

        vm.expectRevert(abi.encodeWithSignature("OnlyVault()"));
        strategy.deposit(allocation);
    }

    function test_RevertsIfGaugeIsShutdown() public {
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.isShutdown.selector, gauge), abi.encode(true)
        );

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSignature("GaugeShutdown()"));
        strategy.deposit(allocation);
    }

    function test_CorrectlyDepositsToLocker() public {
        /// Initial balances are 0.
        assertEq(stakingToken.balanceOf(address(locker)), 0);
        assertEq(stakingToken.balanceOf(address(sidecar1)), 0);
        assertEq(stakingToken.balanceOf(address(sidecar2)), 0);

        uint128 feeSubjectAmount = 50;
        uint128 totalAmount = 100;
        /// Cheat PendingRewards.
        strategy._cheat_setSyncRewards(feeSubjectAmount, totalAmount);

        /// Mint Rewards.
        rewardToken.mint(address(locker), 50);
        rewardToken.mint(address(sidecar1), 20);
        rewardToken.mint(address(sidecar2), 30);

        vm.prank(vault);
        Strategy.PendingRewards memory rewards = strategy.deposit(allocation);

        /// 1. It correctly deposits the specified amount.
        assertEq(stakingToken.balanceOf(address(locker)), allocation.amounts[0]);
        assertEq(stakingToken.balanceOf(address(sidecar1)), allocation.amounts[1]);
        assertEq(stakingToken.balanceOf(address(sidecar2)), allocation.amounts[2]);

        /// 2. It update balances correctly.
        uint256 totalDeposited = allocation.amounts[0] + allocation.amounts[1] + allocation.amounts[2];
        assertEq(strategy.balanceOf(gauge), totalDeposited);

        /// 3. It updates the pending rewards correctly.
        assertEq(rewards.feeSubjectAmount, feeSubjectAmount);
        assertEq(rewards.totalAmount, totalAmount);
    }
}
