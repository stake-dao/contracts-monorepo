// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {CurveAccumulator} from "src/integrations/curve/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract CurveAccumulator__getters is AccumulatorTest {
    constructor() AccumulatorTest(CurveProtocol.CRV_USD, CurveProtocol.CRV, CurveLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new CurveAccumulator(gauge, locker, governance, locker));
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version

        assertEq(CurveAccumulator(accumulator).version(), "4.0.0");
    }

    function test_ReturnsTheName() external view {
        // it returns the name

        assertEq(CurveAccumulator(accumulator).name(), "CurveAccumulator");
    }
}
