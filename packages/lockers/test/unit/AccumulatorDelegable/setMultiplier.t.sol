// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {DelegableAccumulatorTest} from "test/unit/AccumulatorDelegable/utils/DelegableAccumulatorTest.t.sol";

contract DelegableAccumulator__setMultiplier is DelegableAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        delegableAccumulator.setMultiplier(14);
    }

    function test_SetsTheMultiplier(uint256 _multiplier) external {
        // it sets the multiplier

        vm.assume(_multiplier != delegableAccumulator.multiplier());

        vm.prank(governance);
        delegableAccumulator.setMultiplier(_multiplier);

        assertEq(delegableAccumulator.multiplier(), _multiplier);
    }

    function test_EmitsAnEvent(uint256 _multiplier) external {
        // it emits an event

        vm.expectEmit();
        emit MultiplierSet(delegableAccumulator.multiplier(), _multiplier);

        vm.prank(governance);
        delegableAccumulator.setMultiplier(_multiplier);
    }

    /// @notice Event emitted when the multiplier is set
    event MultiplierSet(uint256 oldMultiplier, uint256 newMultiplier);
}
