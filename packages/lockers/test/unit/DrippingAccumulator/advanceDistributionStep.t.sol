// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DrippingAccumulator} from "src/common/accumulator/DrippingAccumulator.sol";
import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__advanceDistributionStep is DrippingAccumulatorTest {
    function test_RevertsIfTheDistributionIsNotStartedYet() external {
        // it reverts if the distribution is not started yet

        vm.expectRevert(DrippingAccumulator.DISTRIBUTION_NOT_STARTED.selector);
        accumulator._expose_advanceDistributionStep();
    }

    function test_RevertsIfTheDistributionIsAlreadyOver() external {
        // it reverts if the distribution is already over

        // start a new distribution and consume all the steps of the distribution
        _cheat_startDistribution();
        _cheat_consumeAllSteps();

        // try to move to the inexistent next step of the distribution
        vm.expectRevert(DrippingAccumulator.DISTRIBUTION_ALREADY_OVER.selector);
        accumulator._expose_advanceDistributionStep();
    }

    function test_RevertsIfTheStepHasAlreadyBeenDistributed() external {
        // it reverts if the step has already been distributed

        // start a new distribution
        _cheat_startDistribution();

        // move to the next step of the distribution
        accumulator._expose_advanceDistributionStep();

        // try to distribute again the step
        vm.expectRevert(DrippingAccumulator.STEP_ALREADY_DISTRIBUTED.selector);
        accumulator._expose_advanceDistributionStep();
    }

    function test_MovesToTheNextStepOfTheDistribution(uint256 currentTimestamp) external {
        // it moves to the next step of the distribution

        // bound the fuzzed timestamp to not exactly be a multiple of 1 week
        vm.assume(currentTimestamp % 1 weeks != 0);
        vm.warp(currentTimestamp);

        // start a new distribution
        _cheat_startDistribution();

        // move to the next step of the distribution
        accumulator._expose_advanceDistributionStep();

        // check the new parameters of the distribution
        uint256 currentWeekTimestamp = accumulator._expose_getCurrentWeekTimestamp();
        (uint120 timestamp, uint120 nextStepTimestamp, uint16 remainingSteps) = accumulator.distribution();
        assertEq(timestamp, currentWeekTimestamp);
        // because the next step timestamp must be a multiple of 1 week
        assertEq(nextStepTimestamp, currentWeekTimestamp + 1 weeks);
        // because the fuzzed timestamp does not match the start of the week (thursday 00:00 UTC)
        assertNotEq(nextStepTimestamp, block.timestamp + 1 weeks);
        assertEq(remainingSteps, periodLength - 1);
    }

    function test_EmitsAnEvent() external {
        // it emits an event

        // start a new distribution
        _cheat_startDistribution();

        (, uint120 nextStepTimestamp, uint16 remainingSteps) = accumulator.distribution();

        vm.expectEmit(true, true, true, true);
        emit NewDistributionStepStarted(nextStepTimestamp + 1 weeks, remainingSteps - 1);
        accumulator._expose_advanceDistributionStep();
    }

    event NewDistributionStepStarted(uint256 nextStepTimestamp, uint16 remainingSteps);
}
