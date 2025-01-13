// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/fx/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

import {BaseZeroLendTokenTest} from "test/linea/zerolend/common/BaseZeroLendTokenTest.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";

contract ZLTokenAccumulator is BaseZeroLendTokenTest, BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(
            14_369_758,
            "linea",
            locker,
            sdToken,
            veToken,
            address(liquidityGauge),
            address(zeroToken),
            address(zeroToken)
        )
    {}

    function _deployAccumulator()
        internal
        override(BaseAccumulatorTest, BaseZeroLendTokenTest)
        returns (address payable)
    {
        _createLabels();

        sdToken = _deploySdZero();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deployLocker();
        accumulator = BaseAccumulator(BaseZeroLendTokenTest._deployAccumulator());
        depositor = IDepositor(_deployDepositor());

        _getSomeZeroTokens(address(this));
        _setupContractGovernance();

        return payable(address(accumulator));
    }
}
