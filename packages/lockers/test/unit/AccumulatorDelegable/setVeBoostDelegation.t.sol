// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {DelegableAccumulatorTest} from "test/unit/AccumulatorDelegable/utils/DelegableAccumulatorTest.t.sol";

contract DelegableAccumulator__setVeBoostDelegation is DelegableAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        delegableAccumulator.setVeBoostDelegation(makeAddr("veBoostDelegation"));
    }

    function test_SetsTheVeBoostDelegation(address _veBoostDelegation) external {
        // it sets the veBoostDelegation

        vm.assume(_veBoostDelegation != address(delegableAccumulator.veBoostDelegation()));

        vm.prank(governance);
        delegableAccumulator.setVeBoostDelegation(_veBoostDelegation);

        assertEq(delegableAccumulator.veBoostDelegation(), _veBoostDelegation);
    }

    function test_EmitsAnEvent(address _veBoostDelegation) external {
        // it emits an event

        vm.expectEmit();
        emit VeBoostDelegationSet(delegableAccumulator.veBoostDelegation(), _veBoostDelegation);

        vm.prank(governance);
        delegableAccumulator.setVeBoostDelegation(_veBoostDelegation);
    }

    /// @notice Event emitted when the veBoostDelegation is set
    event VeBoostDelegationSet(address oldVeBoostDelegation, address newVeBoostDelegation);
}
