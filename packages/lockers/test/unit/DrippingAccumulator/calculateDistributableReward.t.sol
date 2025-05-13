// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.19 <0.9.0;

import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__calculateDistributableReward is DrippingAccumulatorTest {
    function test_Returns0IfTheDistributionIsOver() external {
        // it returns 0 if the distribution is over

        // start a new distribution and consume all the steps of the distribution
        _cheat_startDistribution();
        _cheat_consumeAllSteps();

        // calculate the distributable reward
        assertEq(accumulator._expose_calculateDistributableReward(), 0);
    }

    function test_Returns0IfTheCurrentWeekTimestampIsBeforeTheNextStepTimestamp() external {
        // it returns 0 if the current week timestamp is before the next step timestamp

        // start a new distribution
        _cheat_startDistribution();

        // fetch the initial parameters of the distribution
        (, uint120 nextStepTimestamp,) = accumulator.distribution();

        // warp to a timestamp before the next step timestamp
        vm.warp(nextStepTimestamp - 1);

        // calculate the distributable reward
        assertEq(accumulator._expose_calculateDistributableReward(), 0);
    }

    function test_Returns0IfTheAccumulatorHasNoRewardToken() external {
        // it returns 0 if the accumulator has no reward token

        // start a new distribution
        _cheat_startDistribution();

        // empty the balance of the reward token in the accumulator
        deal(address(rewardToken), address(accumulator), 0);

        // calculate the distributable reward
        assertEq(accumulator._expose_calculateDistributableReward(), 0);
    }

    function test_ReturnsTheCorrectRewardDependingOnTheRemainingSteps() external {
        // it returns the correct reward depending on the remaining steps
    }
}
