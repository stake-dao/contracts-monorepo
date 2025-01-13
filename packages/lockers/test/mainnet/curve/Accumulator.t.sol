// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/curve/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    address public constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public constant CONVEX_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    IVeBoost public veBoost = IVeBoost(0xD37A6aa3d8460Bd2b6536d608103D880695A23CD);

    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(0xe1F9C8ebBC80A013cAf0940fdD1A8554d763b9cf);

    constructor()
        BaseAccumulatorTest(20_661_622, "mainnet", CRV.LOCKER, CRV.SDTOKEN, Curve.VECRV, CRV.GAUGE, CRV_USD, CRV.TOKEN)
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

        /// For the purpose of parent tests, we reset veBoost and veBoostDelegation to the test contract.
        Accumulator(accumulator).setVeBoost(address(0));
        Accumulator(accumulator).setVeBoostDelegation(address(0));
    }

    function test_shareWithDelegation() public {
        Accumulator accumulator = Accumulator(payable(accumulator));

        accumulator.setVeBoost(address(veBoost));
        accumulator.setVeBoostDelegation(address(veBoostDelegation));

        /// Reset the current balance of the delegation contract.
        deal(CRV.TOKEN, address(veBoostDelegation), 0);

        /// Mint some CRV tokens to the accumulator.
        deal(CRV.TOKEN, address(accumulator), 1_000_000e18);

        uint256 snapshotGaugeBalance = ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge));

        uint256 epoch = block.timestamp / 1 weeks * 1 weeks;

        vm.prank(CONVEX_PROXY);
        veBoost.boost(CRV.LOCKER, 1_000_000e18, epoch + 50 weeks, CONVEX_PROXY);

        uint256 sizeDelegation = veBoost.received_balance(CRV.LOCKER);
        uint256 sizeLocker = veBoost.balanceOf(CRV.LOCKER) - sizeDelegation;

        uint256 bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        uint256 expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        // Notify the reward.
        accumulator.notifyReward(CRV.TOKEN, false, false);

        assertEq(ERC20(CRV.TOKEN).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );

        /// Set multiplier.
        /// Distribute only 90% of the share to the delegation contract.
        accumulator.setMultiplier(9e17);

        /// Reset the current balance of the delegation contract.
        deal(CRV.TOKEN, address(veBoostDelegation), 0);

        /// Mint some CRV tokens to the accumulator.
        deal(CRV.TOKEN, address(accumulator), 1_000_000e18);

        snapshotGaugeBalance = ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge));

        sizeDelegation = veBoost.received_balance(CRV.LOCKER);
        sizeLocker = veBoost.balanceOf(CRV.LOCKER) - sizeDelegation;

        bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Apply the multiplier.
        expectedDelegation = expectedDelegation * 9e17 / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(CRV.TOKEN, false, false);

        assertEq(ERC20(CRV.TOKEN).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );
    }
}
