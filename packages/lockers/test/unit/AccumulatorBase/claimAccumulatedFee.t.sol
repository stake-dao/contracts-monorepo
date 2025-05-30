// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IAccountant} from "src/interfaces/IAccountant.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__claimAccumulatedFee is BaseAccumulatorTest {
    function test_RevertsIfTheAccountantIsNotSet() external {
        // it reverts if the accountant is not set

        vm.expectRevert();
        baseAccumulator._expose_claimAccumulatedFee();
    }

    function test_CallTheAccountantForClaimingTheAccumulatedFee() external {
        // it claims the accumulated fee from the accountant

        // set the accountant
        vm.prank(governance);
        baseAccumulator.setAccountant(address(accountant));

        vm.expectCall(address(accountant), abi.encodeWithSelector(IAccountant.claimProtocolFees.selector));
        baseAccumulator._expose_claimAccumulatedFee();
    }
}
