// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__receive is BaseAccumulatorTest {
    function test_CanReceiveETH(uint256 amount) external {
        // it can receive ETH

        vm.assume(amount > 0);

        vm.deal(address(this), amount);
        assertEq(address(baseAccumulator).balance, 0);

        address(baseAccumulator).call{value: amount}("");
        assertEq(address(baseAccumulator).balance, amount);
    }
}
