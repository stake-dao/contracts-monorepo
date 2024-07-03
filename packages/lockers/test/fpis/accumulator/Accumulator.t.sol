// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/base/BaseAccumulatorTest.sol";
import "herdaddy/interfaces/frax/IFraxShares.sol";
import "src/frax/fpis/accumulator/FPISAccumulatorV3.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(20_187_867, FPIS.LOCKER, FPIS.SDTOKEN, Frax.VEFPIS, FPIS.GAUGE, FPIS.TOKEN, FPIS.TOKEN)
    {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new FPISAccumulatorV3(address(liquidityGauge), locker, address(this)));
    }
}
