// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorHarness} from "test/unit/BaseAccumulator/utils/BaseAccumulatorHarness.sol";
import {Test} from "forge-std/src/Test.sol";

contract BaseAccumulator__constructor is Test {
    function test_RevertsIfTheGivenGaugeIsTheZeroAddress() external {
        // it reverts if the given gauge is the zero address

        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        new BaseAccumulatorHarness(address(0), makeAddr("rewardToken"), makeAddr("locker"), makeAddr("governance"));
    }

    function test_RevertsIfTheGivenLockerIsTheZeroAddress() external {
        // it reverts if the given locker is the zero address

        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        new BaseAccumulatorHarness(makeAddr("gauge"), makeAddr("rewardToken"), address(0), makeAddr("governance"));
    }

    function test_RevertsIfTheGivenGovernanceIsTheZeroAddress() external {
        // it reverts if the given governance is the zero address

        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        new BaseAccumulatorHarness(makeAddr("gauge"), makeAddr("rewardToken"), makeAddr("locker"), address(0));
    }

    function test_RevertsIfTheGivenRewardTokenIsTheZeroAddress() external {
        // it reverts if the given reward token is the zero address

        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        new BaseAccumulatorHarness(makeAddr("gauge"), address(0), makeAddr("locker"), makeAddr("governance"));
    }

    function test_InitializesTheGaugeToTheGivenGauge(address gauge) external {
        // it initializes the gauge to the given gauge

        vm.assume(gauge != address(0));

        BaseAccumulatorHarness accumulator =
            new BaseAccumulatorHarness(gauge, makeAddr("rewardToken"), makeAddr("locker"), makeAddr("governance"));

        assertEq(accumulator.gauge(), gauge);
    }

    function test_InitializesTheLockerToTheGivenLocker(address locker) external {
        // it initializes the locker to the given locker

        vm.assume(locker != address(0));

        BaseAccumulatorHarness accumulator =
            new BaseAccumulatorHarness(makeAddr("gauge"), makeAddr("rewardToken"), locker, makeAddr("governance"));

        assertEq(accumulator.locker(), locker);
    }

    function test_InitializesTheRewardTokenToTheGivenRewardToken(address rewardToken) external {
        // it initializes the reward token to the given reward token

        vm.assume(rewardToken != address(0));

        BaseAccumulatorHarness accumulator =
            new BaseAccumulatorHarness(makeAddr("gauge"), rewardToken, makeAddr("locker"), makeAddr("governance"));

        assertEq(accumulator.rewardToken(), rewardToken);
    }

    function test_InitializesTheGovernanceToTheGivenGovernance(address governance) external {
        // it initializes the governance to the given governance

        vm.assume(governance != address(0));

        BaseAccumulatorHarness accumulator =
            new BaseAccumulatorHarness(makeAddr("gauge"), makeAddr("rewardToken"), makeAddr("locker"), governance);

        assertEq(accumulator.governance(), governance);
    }

    function test_InitializesTheClaimerFee() external {
        // it initializes the claimer fee

        BaseAccumulatorHarness accumulator = new BaseAccumulatorHarness(
            makeAddr("gauge"), makeAddr("rewardToken"), makeAddr("locker"), makeAddr("governance")
        );

        assertNotEq(accumulator.claimerFee(), 0);
    }
}
