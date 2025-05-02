// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/common/BaseAccumulatorTest.sol";
import {Yearn} from "address-book/src/protocols/1.sol";
import {YFI} from "address-book/src/lockers/1.sol";

contract YearnAccumulatorTest is BaseAccumulatorTest {
    address internal constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    constructor()
        BaseAccumulatorTest(20_187_867, "mainnet", YFI.LOCKER, YFI.SDTOKEN, Yearn.VEYFI, YFI.GAUGE, DYFI, YFI.TOKEN)
    {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new YearnAccumulator(address(liquidityGauge), locker, address(this), locker));
    }
}
