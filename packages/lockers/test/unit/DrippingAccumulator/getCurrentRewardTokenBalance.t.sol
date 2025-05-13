// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.19 <0.9.0;

import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__getCurrentRewardTokenBalance is DrippingAccumulatorTest {
    function test_ReturnsTheCorrectBalance(uint256 balance) external {
        // it returns the correct balance

        deal(address(rewardToken), address(accumulator), balance);

        assertEq(accumulator._expose_getCurrentRewardTokenBalance(), balance);
    }
}
