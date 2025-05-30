// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__setFeeReceiver is BaseAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        baseAccumulator.setFeeReceiver(makeAddr("feeReceiver"));
    }

    function test_SetsTheFeeReceiverToTheGivenFeeReceiver(address feeReceiver) external {
        // it sets the fee receiver to the given fee receiver

        vm.assume(feeReceiver != address(0));

        vm.prank(baseAccumulator.governance());
        baseAccumulator.setFeeReceiver(feeReceiver);
    }

    function test_EmitsAEvent(address feeReceiver) external {
        // it emits a event

        vm.assume(feeReceiver != address(0));

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit FeeReceiverUpdated(feeReceiver);
        baseAccumulator.setFeeReceiver(feeReceiver);
    }

    /// @notice Event emitted when the fee receiver is updated
    event FeeReceiverUpdated(address newFeeReceiver);
}
