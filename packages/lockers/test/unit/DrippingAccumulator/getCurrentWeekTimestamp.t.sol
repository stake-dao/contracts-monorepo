// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.19 <0.9.0;

import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__getCurrentWeekTimestamp is DrippingAccumulatorTest {
    function test_ReturnsTheCorrectTimestamp(uint256 timestamp, uint256 offset) external {
        // it returns the correct timestamp

        // bound the fuzzed values
        timestamp = bound(timestamp, 0, type(uint256).max - 2 weeks);
        offset = offset % 1 weeks;

        // warp to the fuzzed timestamp
        vm.warp(timestamp);

        // fetch the current week timestamp associated to the fuzzed timestamp and assert it is a multiple of 1 week
        uint256 initialweekTimestamp = accumulator._expose_getCurrentWeekTimestamp();
        assertEq(initialweekTimestamp % 1 weeks, 0);

        // assert any timestamp in the same week leads to the same current week timestamp
        vm.warp(initialweekTimestamp + offset);
        assertEq(initialweekTimestamp, accumulator._expose_getCurrentWeekTimestamp());

        // assert the returned value is different after 1 week
        vm.warp(initialweekTimestamp + 1 weeks);
        uint256 newWeekTimestamp = accumulator._expose_getCurrentWeekTimestamp();
        assertNotEq(initialweekTimestamp, newWeekTimestamp);

        // // assert the returned value is the same for any timestamp in the same week
        vm.warp(newWeekTimestamp + offset);
        assertEq(newWeekTimestamp, accumulator._expose_getCurrentWeekTimestamp());
    }
}
