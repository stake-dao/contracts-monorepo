// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/curve/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    address public constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    constructor()
        BaseAccumulatorTest(20_169_332, CRV.LOCKER, CRV.SDTOKEN, Curve.VECRV, CRV.GAUGE, CRV_USD, CRV.TOKEN)
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new Accumulator(address(liquidityGauge), locker, address(this)));

        /// Setup new Fee Distributor.
        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setAccumulator(address(accumulator));

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setFeeDistributor(address(Curve.FEE_DISTRIBUTOR));

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setFeeRewardToken(address(CRV_USD));
    }
}