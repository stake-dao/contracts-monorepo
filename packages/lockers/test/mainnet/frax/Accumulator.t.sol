// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/common/BaseAccumulatorTest.sol";

import "src/mainnet/fxs/Accumulator.sol";
import "common/interfaces/frax/IFraxShares.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(20_187_867, FXS.LOCKER, FXS.SDTOKEN, Frax.VEFXS, FXS.GAUGE, FXS.TOKEN, FXS.TOKEN)
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        /// Disable tracking votes in order to mint any amount of FXS for testing purposes.
        vm.prank(IFraxShares(FXS.TOKEN).owner_address());
        IFraxShares(FXS.TOKEN).toggleVotes();

        accumulator = payable(new Accumulator(address(liquidityGauge), locker, address(this)));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }
}
