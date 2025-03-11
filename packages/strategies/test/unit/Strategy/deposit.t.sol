// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";
import {MockSidecar} from "test/mocks/MockSidecar.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract Strategy__deposit is StrategyBaseTest {
    address internal gauge;
    address internal sidecar1;
    address internal sidecar2;

    IAllocator.Allocation internal allocation;

    function setUp() public override {
        super.setUp();

        gauge = address(stakingToken);
        sidecar1 = address(new MockSidecar(gauge, address(rewardToken), accountant));
        sidecar2 = address(new MockSidecar(gauge, address(rewardToken), accountant));

        // Mock the vault function of the IProtocolController interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.vaults.selector, gauge),
            abi.encode(address(vault))
        );

        address[] memory targets = new address[](3);
        targets[0] = address(locker);
        targets[1] = sidecar1;
        targets[2] = sidecar2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        allocation = IAllocator.Allocation({gauge: gauge, harvested: false, targets: targets, amounts: amounts});

        // Mock AllocationTargets
        vm.mockCall(
            address(allocator),
            abi.encodeWithSelector(IAllocator.getAllocationTargets.selector, gauge),
            abi.encode(targets)
        );
    }

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
