// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__receive is BaseAccumulatorTest {
    function test_CanReceiveETH(uint256 amount) external {
        // it can receive ETH

        vm.assume(amount > 0);

        vm.deal(address(this), amount);
        assertEq(address(baseAccumulator).balance, 0);

        (bool success,) = address(baseAccumulator).call{value: amount}("");
        assertEq(success, true);
        assertEq(address(baseAccumulator).balance, amount);
    }
}
