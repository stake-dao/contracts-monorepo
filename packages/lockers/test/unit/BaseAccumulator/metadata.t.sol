// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__metadata is BaseAccumulatorTest {
    function test_ReturnsTheNameOfTheContract() external view {
        // it returns the name of the contract

        assertEq(baseAccumulator.name(), type(BaseAccumulator).name);
    }

    function test_ReturnsTheVersionOfTheContract() external view {
        // it returns the version of the contract

        assertEq(baseAccumulator.version(), "3.0.0");
    }
}
