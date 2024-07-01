// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/base/AccumulatorV3.t.sol";
import "herdaddy/interfaces/frax/IFraxShares.sol";
import "src/frax/fxs/accumulator/FXSAccumulatorV3.sol";

contract FXSAccumulatorV3IntegrationTest is AccumulatorV2Test {
    constructor() AccumulatorV2Test(20_187_867, FXS.LOCKER, FXS.SDTOKEN, Frax.VEFXS, FXS.GAUGE, FXS.TOKEN, FXS.TOKEN) {}

    function _deployAccumulator() internal override returns (address payable) {
        /// Disable tracking votes in order to mint any amount of FXS for testing purposes.
        vm.prank(IFraxShares(FXS.TOKEN).owner_address());
        IFraxShares(FXS.TOKEN).toggleVotes();

        return payable(new FXSAccumulatorV3(address(liquidityGauge), locker, address(this)));
    }
}
