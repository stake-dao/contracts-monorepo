// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {IStrategy} from "common/interfaces/stake-dao/IStrategy.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IVeBoost} from "src/common/interfaces/IVeBoost.sol";
import {IVeBoostDelegation} from "src/common/interfaces/IVeBoostDelegation.sol";
import {CurveAccumulator} from "src/mainnet/curve/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/common/BaseAccumulatorTest.sol";

contract CurveAccumulatorTest is BaseAccumulatorTest {
    address public constant CONVEX_PROXY = CurveProtocol.CONVEX_PROXY;

    IVeBoost public veBoost = IVeBoost(CurveProtocol.VE_BOOST);
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(CurveProtocol.VE_BOOST_DELEGATION);

    constructor()
        BaseAccumulatorTest(
            20_661_622, // blockNumber
            "mainnet", // chain
            CurveLocker.LOCKER, // locker
            CurveLocker.SDTOKEN, // sdToken
            CurveProtocol.VECRV, // veToken
            CurveLocker.GAUGE, // liquidityGauge
            CurveProtocol.CRV_USD, // rewardToken
            CurveProtocol.CRV // strategyRewardToken
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new CurveAccumulator(address(liquidityGauge), locker, address(this), locker));

        address governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

        /// Setup new Fee Distributor.
        vm.prank(governance);
        IStrategy(CurveLocker.STRATEGY).setAccumulator(address(accumulator));

        vm.prank(governance);
        IStrategy(CurveLocker.STRATEGY).setFeeDistributor(address(CurveProtocol.FEE_DISTRIBUTOR));
        vm.prank(governance);
        IStrategy(CurveLocker.STRATEGY).setFeeRewardToken(CurveProtocol.CRV_USD);

        /// For the purpose of parent tests, we reset veBoost and veBoostDelegation to the test contract.
        CurveAccumulator(accumulator).setVeBoost(address(0));
        CurveAccumulator(accumulator).setVeBoostDelegation(address(0));
    }

    function test_shareWithDelegation() public {
        CurveAccumulator accumulator = CurveAccumulator(payable(accumulator));

        accumulator.setVeBoost(address(veBoost));
        accumulator.setVeBoostDelegation(address(veBoostDelegation));

        /// Reset the current balance of the delegation contract.
        deal(CurveLocker.TOKEN, address(veBoostDelegation), 0);

        /// Mint some CRV tokens to the accumulator.
        deal(CurveLocker.TOKEN, address(accumulator), 1_000_000e18);

        uint256 snapshotGaugeBalance = ERC20(CurveLocker.TOKEN).balanceOf(address(liquidityGauge));

        uint256 epoch = block.timestamp / 1 weeks * 1 weeks;

        vm.prank(CONVEX_PROXY);
        veBoost.boost(CurveLocker.LOCKER, 1_000_000e18, epoch + 50 weeks, CONVEX_PROXY);

        uint256 sizeDelegation = veBoost.received_balance(CurveLocker.LOCKER);
        uint256 sizeLocker = veBoost.balanceOf(CurveLocker.LOCKER) - sizeDelegation;

        uint256 bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        uint256 expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        // Notify the reward.
        accumulator.notifyReward(CurveLocker.TOKEN);

        assertEq(ERC20(CurveLocker.TOKEN).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(CurveLocker.TOKEN).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );

        /// Set multiplier.
        /// Distribute only 90% of the share to the delegation contract.
        accumulator.setMultiplier(9e17);

        /// Reset the current balance of the delegation contract.
        deal(CurveLocker.TOKEN, address(veBoostDelegation), 0);

        /// Mint some CRV tokens to the accumulator.
        deal(CurveLocker.TOKEN, address(accumulator), 1_000_000e18);

        snapshotGaugeBalance = ERC20(CurveLocker.TOKEN).balanceOf(address(liquidityGauge));

        sizeDelegation = veBoost.received_balance(CurveLocker.LOCKER);
        sizeLocker = veBoost.balanceOf(CurveLocker.LOCKER) - sizeDelegation;

        bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Apply the multiplier.
        expectedDelegation = expectedDelegation * 9e17 / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(CurveLocker.TOKEN);

        assertEq(ERC20(CurveLocker.TOKEN).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(CurveLocker.TOKEN).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );
    }
}
