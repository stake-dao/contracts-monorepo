// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/common/BaseAccumulatorTest.sol";

import "src/mainnet/fpis/Accumulator.sol";
import "common/interfaces/frax/IFraxShares.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(
            20_187_867,
            "mainnet",
            FPIS.LOCKER,
            FPIS.SDTOKEN,
            Frax.VEFPIS,
            FPIS.GAUGE,
            FPIS.TOKEN,
            FPIS.TOKEN
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new Accumulator(address(liquidityGauge), locker, address(this)));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }
}
