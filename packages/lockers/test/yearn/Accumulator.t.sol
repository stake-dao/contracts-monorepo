// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/common/BaseAccumulatorTest.sol";
import "src/mainnet/yearn/accumulator/YFIAccumulator.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    address internal constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    constructor() BaseAccumulatorTest(20_187_867, YFI.LOCKER, YFI.SDTOKEN, Yearn.VEYFI, YFI.GAUGE, DYFI, YFI.TOKEN) {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new YFIAccumulator(address(liquidityGauge), locker, address(this)));
    }
}
