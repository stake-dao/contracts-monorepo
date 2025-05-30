// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__setAccountant is BaseAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        baseAccumulator.setAccountant(makeAddr("accountant"));
    }

    function test_RevertsIfTheGivenAccountantIsTheZeroAddress() external {
        // it reverts if the given accountant is the zero address

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(AccumulatorBase.ZERO_ADDRESS.selector);
        baseAccumulator.setAccountant(address(0));
    }

    function test_SetsTheAccountantToTheGivenAccountant(address accountant) external {
        // it sets the accountant to the given accountant

        vm.assume(accountant != address(0));

        vm.prank(baseAccumulator.governance());
        baseAccumulator.setAccountant(accountant);
    }

    function test_EmitsAEvent(address accountant) external {
        // it emits a event

        vm.assume(accountant != address(0));

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit AccountantUpdated(accountant);
        baseAccumulator.setAccountant(accountant);
    }

    /// @notice Event emitted when the accountant is updated
    event AccountantUpdated(address newAccountant);
}
