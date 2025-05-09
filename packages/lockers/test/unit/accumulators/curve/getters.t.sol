// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {CurveAccumulator} from "src/mainnet/curve/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";
import {Curve} from "address-book/src/protocols/1.sol";
import {CRV as CurveLocker} from "address-book/src/lockers/1.sol";

contract CurveAccumulator__getters is AccumulatorTest {
    constructor() AccumulatorTest(Curve.CRV_USD, Curve.CRV, CurveLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new CurveAccumulator(gauge, locker, governance, locker));
    }

    function test_ReturnsTheVersion() external {
        // it returns the version

        assertEq(CurveAccumulator(accumulator).version(), "4.0.0");
    }

    function test_ReturnsTheName() external {
        // it returns the name

        assertEq(CurveAccumulator(accumulator).name(), "CurveAccumulator");
    }
}
