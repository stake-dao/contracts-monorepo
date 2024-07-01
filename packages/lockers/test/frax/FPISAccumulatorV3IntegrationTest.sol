// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/base/AccumulatorV3.t.sol";
import "herdaddy/interfaces/frax/IFraxShares.sol";
import "src/frax/fpis/accumulator/FPISAccumulatorV3.sol";

contract FPISAccumulatorV3IntegrationTest is AccumulatorV2Test {
    constructor() AccumulatorV2Test(20_187_867, FPIS.LOCKER, FPIS.SDTOKEN, Frax.VEFPIS, FPIS.GAUGE, FPIS.TOKEN, FPIS.TOKEN) {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new FPISAccumulatorV3(address(liquidityGauge), locker, address(this)));
    }
}
