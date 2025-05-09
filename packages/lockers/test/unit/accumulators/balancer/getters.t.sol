// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BalancerAccumulator} from "src/mainnet/balancer/Accumulator.sol";
import {Balancer as BalancerProtocol} from "address-book/src/protocols/1.sol";
import {BAL as BalancerLocker} from "address-book/src/lockers/1.sol";
import {CommonAddresses} from "address-book/src/common.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract BalancerAccumulator__getters is AccumulatorTest {
    constructor() AccumulatorTest(CommonAddresses.USDC, BalancerProtocol.BAL, BalancerLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new BalancerAccumulator(gauge, locker, governance, locker));
    }

    function test_ReturnsTheVersion() external {
        // it returns the version

        assertEq(BalancerAccumulator(accumulator).version(), "4.0.0");
    }

    function test_ReturnsTheName() external {
        // it returns the name

        assertEq(BalancerAccumulator(accumulator).name(), "BalancerAccumulator");
    }
}
