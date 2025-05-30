// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__setClaimerFee is BaseAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        baseAccumulator.setClaimerFee(100);
    }

    function test_RevertsIfTheGivenclaimerFeeIsGreaterThanTheDenominator(uint256 claimerFee) external {
        // it reverts if the given claimer free is greater than the denominator

        vm.assume(claimerFee > baseAccumulator.DENOMINATOR());

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(AccumulatorBase.FEE_TOO_HIGH.selector);
        baseAccumulator.setClaimerFee(claimerFee);
    }

    function test_SetsTheclaimerFeeToTheGivenclaimerFee(uint256 claimerFee) external {
        // it sets the claimer free to the given claimer free

        vm.assume(claimerFee <= baseAccumulator.DENOMINATOR());

        vm.prank(baseAccumulator.governance());
        baseAccumulator.setClaimerFee(claimerFee);
    }

    function test_EmitsAEvent(uint256 claimerFee) external {
        // it emits a event

        vm.assume(claimerFee <= baseAccumulator.DENOMINATOR());

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit ClaimerFeeUpdated(claimerFee);
        baseAccumulator.setClaimerFee(claimerFee);
    }

    /// @notice Event emitted when the claimer fee is updated
    event ClaimerFeeUpdated(uint256 newclaimerFee);
}
