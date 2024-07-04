// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/common/BaseAccumulatorTest.sol";

import "src/mainnet/fpis/Accumulator.sol";
import "herdaddy/interfaces/frax/IFraxShares.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(20_187_867, FPIS.LOCKER, FPIS.SDTOKEN, Frax.VEFPIS, FPIS.GAUGE, FPIS.TOKEN, FPIS.TOKEN)
    {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new Accumulator(address(liquidityGauge), locker, address(this)));
    }
}
