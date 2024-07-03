// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/base/BaseAccumulatorTest.sol";
import "herdaddy/interfaces/frax/IFraxShares.sol";
import "src/apwine/accumulator/APWAccumulatorV3.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(
            20_187_867,
            SPECTRA.LOCKER,
            SPECTRA.SDTOKEN,
            Spectra.VEAPW,
            SPECTRA.GAUGE,
            SPECTRA.TOKEN,
            SPECTRA.TOKEN
        )
    {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new APWAccumulatorV3(address(liquidityGauge), locker, address(this)));
    }
}
