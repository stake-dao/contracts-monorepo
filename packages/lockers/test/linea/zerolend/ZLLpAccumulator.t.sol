// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/fx/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

import {BaseZeroLendLpTest} from "test/linea/zerolend/common/BaseZeroLendLpTest.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";

contract ZLLpAccumulator is BaseZeroLendLpTest, BaseAccumulatorTest {
    constructor()
        BaseAccumulatorTest(
            14_369_758,
            "linea",
            locker,
            sdToken,
            veToken,
            address(liquidityGauge),
            address(WETH),
            address(WETH)
        )
    {}

    function _deployAccumulator()
        internal
        override(BaseAccumulatorTest, BaseZeroLendLpTest)
        returns (address payable)
    {
        _createLabels();

        sdToken = _deploySdZeroLp();
        liquidityGauge = ILiquidityGauge(_deployLiquidityGauge(sdToken));
        locker = _deployLpLocker();
        accumulator = BaseAccumulator(BaseZeroLendLpTest._deployAccumulator());
        depositor = IDepositor(_deployLpDepositor());

        _getSomeZeroLpTokens(address(this));
        _setupLpContractGovernance();

        return payable(address(accumulator));
    }
}
