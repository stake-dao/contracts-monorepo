// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__getRemainingSchedule is DrippingAccumulatorTest {
    function test_ReturnsTheCorrectRemainingSteps() external {
        // it returns the correct remaining steps

        // start a new distribution
        _cheat_startDistribution();

        // fetch the initial parameters of the distribution and assert the remaining steps are correct
        (,, uint16 remainingSteps) = accumulator.distribution();
        assertEq(accumulator.getRemainingSchedule(), remainingSteps);

        // ensure the remaining steps are decremented correctly after each step
        for (uint16 i = remainingSteps; i > 0; i--) {
            vm.warp(block.timestamp + 1 weeks);
            accumulator._expose_advanceDistributionStep();
            assertEq(accumulator.getRemainingSchedule(), i - 1);
        }
    }
}
