// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {CurveAccumulator} from "src/mainnet/curve/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/common/BaseAccumulatorTest.sol";
import {IVeBoost} from "src/common/interfaces/IVeBoost.sol";
import {IVeBoostDelegation} from "src/common/interfaces/IVeBoostDelegation.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Curve} from "address-book/src/protocols/1.sol";
import {CRV} from "address-book/src/lockers/1.sol";
import {IStrategy} from "common/interfaces/stake-dao/IStrategy.sol";

contract CurveAccumulatorTest is BaseAccumulatorTest {
    address public constant CONVEX_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    IVeBoost public veBoost = IVeBoost(Curve.VE_BOOST);
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(Curve.VE_BOOST_DELEGATION);

    constructor()
        BaseAccumulatorTest(
            20_661_622, // blockNumber
            "mainnet", // chain
            CRV.LOCKER, // locker
            CRV.SDTOKEN, // sdToken
            Curve.VECRV, // veToken
            CRV.GAUGE, // liquidityGauge
            Curve.CRV_USD, // rewardToken
            Curve.CRV // strategyRewardToken
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new CurveAccumulator(address(liquidityGauge), locker, address(this), locker));

        // TODO: legacy governance address -- This test must be rewritten ASAP
        address governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

        /// Setup new Fee Distributor.
        vm.prank(governance);
        IStrategy(CRV.STRATEGY).setAccumulator(address(accumulator));

        vm.prank(governance);
        IStrategy(CRV.STRATEGY).setFeeDistributor(address(Curve.FEE_DISTRIBUTOR));
        vm.prank(governance);
        IStrategy(CRV.STRATEGY).setFeeRewardToken(Curve.CRV_USD);

        /// For the purpose of parent tests, we reset veBoost and veBoostDelegation to the test contract.
        CurveAccumulator(accumulator).setVeBoost(address(0));
        CurveAccumulator(accumulator).setVeBoostDelegation(address(0));
    }

    function test_shareWithDelegation() public {
        CurveAccumulator accumulator = CurveAccumulator(payable(accumulator));

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
        accumulator.notifyReward(CRV.TOKEN, false);

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
        accumulator.notifyReward({token: CRV.TOKEN, claimFeeStrategy: false});

        assertEq(ERC20(CRV.TOKEN).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );
    }
}
