// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {YearnLocker, YearnProtocol} from "address-book/src/YearnEthereum.sol";
import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/common/BaseAccumulatorTest.sol";

contract YearnAccumulatorTest is BaseAccumulatorTest {
    address internal constant DYFI = YearnProtocol.DYFI;

    constructor()
        BaseAccumulatorTest(
            20_187_867,
            "mainnet",
            YearnLocker.LOCKER,
            YearnLocker.SDTOKEN,
            YearnProtocol.VEYFI,
            YearnLocker.GAUGE,
            DYFI,
            YearnLocker.TOKEN
        )
    {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new YearnAccumulator(address(liquidityGauge), locker, address(this), locker));
    }
}
