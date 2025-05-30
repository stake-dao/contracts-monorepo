// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "address-book/src/BalancerEthereum.sol";
import {Common} from "address-book/src/CommonEthereum.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {IVeBoost} from "src/interfaces/IVeBoost.sol";
import {IVeBoostDelegation} from "src/interfaces/IVeBoostDelegation.sol";
import {BalancerAccumulator} from "src/integrations/balancer/Accumulator.sol";
import {BaseAccumulatorTest} from "test/fork/BaseAccumulatorTest.sol";

contract BalancerAccumulatorTest is BaseAccumulatorTest {
    address internal constant USDC = Common.USDC;

    IVeBoost public veBoost = IVeBoost(BalancerProtocol.VE_BOOST);

    /// @notice Ve Boost FXTLDelegation.
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(BalancerLocker.VE_BOOST_DELEGATION);

    constructor()
        BaseAccumulatorTest(
            20_237_852,
            "mainnet",
            BalancerLocker.LOCKER,
            BalancerLocker.SDTOKEN,
            BalancerProtocol.VEBAL,
            BalancerLocker.GAUGE,
            USDC,
            BalancerProtocol.BAL
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new BalancerAccumulator(address(liquidityGauge), locker, address(this), locker));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));

        /// For the purpose of parent tests, we reset veBoost and veBoostDelegation to the test contract.
        BalancerAccumulator(accumulator).setVeBoost(address(0));
        BalancerAccumulator(accumulator).setVeBoostDelegation(address(0));

        return accumulator;
    }

    function test_shareWithDelegation() public {
        BalancerAccumulator accumulator = BalancerAccumulator(payable(accumulator));

        accumulator.setVeBoost(address(veBoost));
        accumulator.setVeBoostDelegation(address(veBoostDelegation));

        /// Reset the current balance of the delegation contract.
        deal(BalancerProtocol.BAL, address(veBoostDelegation), 0);

        /// Mint some BAL tokens to the accumulator.
        deal(BalancerProtocol.BAL, address(accumulator), 1_000_000e18);

        uint256 snapshotGaugeBalance = ERC20(BalancerProtocol.BAL).balanceOf(address(liquidityGauge));

        uint256 sizeDelegation = veBoost.received_balance(BalancerLocker.LOCKER);
        uint256 sizeLocker = veBoost.balanceOf(BalancerLocker.LOCKER) - sizeDelegation;

        uint256 bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        uint256 expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(BalancerProtocol.BAL);

        assertEq(ERC20(BalancerProtocol.BAL).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(BalancerProtocol.BAL).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );

        /// Set multiplier.
        /// Distribute only 90% of the share to the delegation contract.
        accumulator.setMultiplier(9e17);

        /// Reset the current balance of the delegation contract.
        deal(BalancerProtocol.BAL, address(veBoostDelegation), 0);

        /// Mint some BAL tokens to the accumulator.
        deal(BalancerProtocol.BAL, address(accumulator), 1_000_000e18);

        snapshotGaugeBalance = ERC20(BalancerProtocol.BAL).balanceOf(address(liquidityGauge));

        sizeDelegation = veBoost.received_balance(BalancerLocker.LOCKER);
        sizeLocker = veBoost.balanceOf(BalancerLocker.LOCKER) - sizeDelegation;

        bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Apply the multiplier.
        expectedDelegation = expectedDelegation * 9e17 / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(BalancerProtocol.BAL);

        assertEq(ERC20(BalancerProtocol.BAL).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(BalancerProtocol.BAL).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );
    }
}
