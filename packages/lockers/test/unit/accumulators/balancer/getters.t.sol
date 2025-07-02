// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "@address-book/src/BalancerEthereum.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {BalancerAccumulator} from "src/integrations/balancer/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract BalancerAccumulator__getters is AccumulatorTest {
    constructor() AccumulatorTest(Common.USDC, BalancerProtocol.BAL, BalancerLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new BalancerAccumulator(gauge, locker, governance, locker));
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version

        assertEq(BalancerAccumulator(accumulator).version(), "4.0.0");
    }

    function test_ReturnsTheName() external view {
        // it returns the name

        assertEq(BalancerAccumulator(accumulator).name(), "BalancerAccumulator");
    }
}
