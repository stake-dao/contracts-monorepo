// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DrippingAccumulator} from "src/common/accumulator/DrippingAccumulator.sol";
import {DrippingAccumulatorHarness} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorHarness.sol";

contract DrippingAccumulator__constructor is Test {
    function test_SetsThePeriodLength(uint256 _periodLength) external {
        // it sets the period length

        vm.assume(_periodLength > 0);

        DrippingAccumulator drippingAccumulator = new DrippingAccumulatorHarness(
            makeAddr("gauge"), makeAddr("rewardToken"), makeAddr("locker"), makeAddr("governance"), _periodLength
        );

        assertEq(drippingAccumulator.PERIOD_LENGTH(), _periodLength);
    }

    function test_RevertsIfThePeriodLengthIsZero() external {
        // it reverts if the period length is zero

        vm.expectRevert(PERIOD_LENGTH_IS_ZERO.selector);
        new DrippingAccumulatorHarness(
            makeAddr("gauge"), makeAddr("rewardToken"), makeAddr("locker"), makeAddr("governance"), 0
        );
    }

    /// @notice Error emitted when the period length is 0.
    error PERIOD_LENGTH_IS_ZERO();
}
