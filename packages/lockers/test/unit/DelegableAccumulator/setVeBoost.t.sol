// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {DelegableAccumulatorTest} from "test/unit/DelegableAccumulator/utils/DelegableAccumulatorTest.t.sol";

contract DelegableAccumulator__setVeBoost is DelegableAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.prank(caller);
        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        delegableAccumulator.setVeBoost(makeAddr("veBoost"));
    }

    function test_SetsTheVeBoost(address _veBoost) external {
        // it sets the veBoost

        vm.assume(_veBoost != address(delegableAccumulator.veBoost()));

        vm.prank(governance);
        delegableAccumulator.setVeBoost(_veBoost);

        assertEq(delegableAccumulator.veBoost(), _veBoost);
    }

    function test_EmitsAnEvent(address _veBoost) external {
        // it emits an event

        vm.expectEmit();
        emit VeBoostSet(delegableAccumulator.veBoost(), _veBoost);

        vm.prank(governance);
        delegableAccumulator.setVeBoost(_veBoost);
    }

    /// @notice Event emitted when the veBoost is set
    event VeBoostSet(address oldVeBoost, address newVeBoost);
}
