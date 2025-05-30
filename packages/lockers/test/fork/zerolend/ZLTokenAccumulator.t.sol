// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IDepositor} from "src/interfaces/IDepositor.sol";
import "src/integrations/fx/Accumulator.sol";
import "test/fork/BaseAccumulatorTest.sol";
import {BaseZeroLendTokenTest} from "test/fork/zerolend/common/BaseZeroLendTokenTest.sol";

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
        locker = _deploySafeLocker();
        accumulator = AccumulatorBase(BaseZeroLendTokenTest._deployAccumulator());
        depositor = IDepositor(_deployDepositor());

        _getSomeZeroTokens(address(this));
        _setupContractGovernance();

        return payable(address(accumulator));
    }
}
