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

        gauge = makeAddr("gauge");
        sidecar1 = address(new MockSidecar(makeAddr("asset1")));
        sidecar2 = address(new MockSidecar(makeAddr("asset2")));

        // Mock the vault function of the IProtocolController interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.vaults.selector, gauge),
            abi.encode(address(vault))
        );

        /// Mock the isShutdown function to return false
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.isShutdown.selector, gauge), abi.encode(false)
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
        vm.prank(vault);
        strategy.deposit(allocation);

        assertTrue(true);
    }

    function test_ReturnsCorrectPendingRewardsWhenDepositingToLocker() public {
        uint128 feeSubjectAmount = 50;
        uint128 totalAmount = 100;
        strategy._cheat_setSyncRewards(feeSubjectAmount, totalAmount);

        vm.prank(vault);
        Strategy.PendingRewards memory rewards = strategy.deposit(allocation);

        assertEq(rewards.feeSubjectAmount, feeSubjectAmount);
        assertEq(rewards.totalAmount, totalAmount);
    }

    function test_CorrectlyCallsSidecarDepositFunction() public {
        vm.expectCall(sidecar1, abi.encodeWithSelector(ISidecar.deposit.selector, allocation.amounts[1]));
        vm.expectCall(sidecar2, abi.encodeWithSelector(ISidecar.deposit.selector, allocation.amounts[2]));

        vm.prank(vault);
        strategy.deposit(allocation);
    }

    function test_ReturnsCorrectPendingRewardsWhenDepositingToSidecars() public {
        uint128 feeSubjectAmount = 75;
        uint128 totalAmount = 150;
        strategy._cheat_setSyncRewards(feeSubjectAmount, totalAmount);

        vm.prank(vault);
        Strategy.PendingRewards memory rewards = strategy.deposit(allocation);

        assertEq(rewards.feeSubjectAmount, feeSubjectAmount);
        assertEq(rewards.totalAmount, totalAmount);
    }

    function test_CorrectlyHandlesZeroAmountDeposits() public {
        address[] memory targets = new address[](3);
        targets[0] = address(locker);
        targets[1] = sidecar1;
        targets[2] = sidecar2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 0;
        amounts[2] = 0;

        IAllocator.Allocation memory zeroAllocation =
            IAllocator.Allocation({gauge: gauge, harvested: false, targets: targets, amounts: amounts});

        uint128 feeSubjectAmount = 25;
        uint128 totalAmount = 50;
        strategy._cheat_setSyncRewards(feeSubjectAmount, totalAmount);

        vm.prank(vault);
        Strategy.PendingRewards memory rewards = strategy.deposit(zeroAllocation);

        assertEq(rewards.feeSubjectAmount, feeSubjectAmount);
        assertEq(rewards.totalAmount, totalAmount);
    }
}
