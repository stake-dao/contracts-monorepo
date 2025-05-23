// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Common} from "address-book/src/CommonEthereum.sol";
import {FXNLocker, FXNProtocol} from "address-book/src/FXNEthereum.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {FXNAccumulator} from "src/mainnet/fx/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/common/BaseAccumulatorTest.sol";

contract FXAccumulatorTest is BaseAccumulatorTest {
    address internal constant WSETH = Common.WSTETH;

    constructor()
        BaseAccumulatorTest(
            20_187_797,
            "mainnet",
            FXNLocker.LOCKER,
            FXNLocker.SDTOKEN,
            FXNProtocol.VEFXN,
            FXNLocker.GAUGE,
            WSETH,
            FXNLocker.TOKEN
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new FXNAccumulator(address(liquidityGauge), locker, address(this)));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }
}
