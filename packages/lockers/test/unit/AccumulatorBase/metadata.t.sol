// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__metadata is BaseAccumulatorTest {
    function test_ReturnsTheNameOfTheContract() external view {
        // it returns the name of the contract

        assertEq(baseAccumulator.name(), type(AccumulatorBase).name);
    }

    function test_ReturnsTheVersionOfTheContract() external view {
        // it returns the version of the contract

        assertEq(baseAccumulator.version(), "3.0.0");
    }
}
