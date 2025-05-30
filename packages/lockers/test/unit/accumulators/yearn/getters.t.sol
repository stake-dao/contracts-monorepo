// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {YearnLocker, YearnProtocol} from "address-book/src/YearnEthereum.sol";
import {YearnAccumulator} from "src/integrations/yearn/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract YearnAccumulator__getters is AccumulatorTest {
    constructor() AccumulatorTest(YearnProtocol.YFI, YearnProtocol.DYFI, YearnLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new YearnAccumulator(gauge, locker, governance, locker));
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version

        assertEq(YearnAccumulator(accumulator).version(), "4.0.0");
    }

    function test_ReturnsTheName() external view {
        // it returns the name

        assertEq(YearnAccumulator(accumulator).name(), "YearnAccumulator");
    }
}
