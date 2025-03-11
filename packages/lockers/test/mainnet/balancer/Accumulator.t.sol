// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/balancer/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IVeBoost public veBoost = IVeBoost(0x67F8DF125B796B05895a6dc8Ecf944b9556ecb0B);

    /// @notice Ve Boost FXTLDelegation.
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(0xda9846665Bdb44b0d0CAFFd0d1D4A539932BeBdf);

    constructor()
        BaseAccumulatorTest(20_237_852, "mainnet", BAL.LOCKER, BAL.SDTOKEN, Balancer.VEBAL, BAL.GAUGE, USDC, Balancer.BAL)
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new Accumulator(address(liquidityGauge), locker, address(this)));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));

        /// For the purpose of parent tests, we reset veBoost and veBoostDelegation to the test contract.
        Accumulator(accumulator).setVeBoost(address(0));
        Accumulator(accumulator).setVeBoostDelegation(address(0));

        return accumulator;
    }

    function test_shareWithDelegation() public {
        Accumulator accumulator = Accumulator(payable(accumulator));

        accumulator.setVeBoost(address(veBoost));
        accumulator.setVeBoostDelegation(address(veBoostDelegation));

        /// Reset the current balance of the delegation contract.
        deal(Balancer.BAL, address(veBoostDelegation), 0);

        /// Mint some BAL tokens to the accumulator.
        deal(Balancer.BAL, address(accumulator), 1_000_000e18);

        uint256 snapshotGaugeBalance = ERC20(Balancer.BAL).balanceOf(address(liquidityGauge));

        uint256 sizeDelegation = veBoost.received_balance(BAL.LOCKER);
        uint256 sizeLocker = veBoost.balanceOf(BAL.LOCKER) - sizeDelegation;

        uint256 bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        uint256 expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(Balancer.BAL, false, false);

        assertEq(ERC20(Balancer.BAL).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(Balancer.BAL).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );

        /// Set multiplier.
        /// Distribute only 90% of the share to the delegation contract.
        accumulator.setMultiplier(9e17);

        /// Reset the current balance of the delegation contract.
        deal(Balancer.BAL, address(veBoostDelegation), 0);

        /// Mint some BAL tokens to the accumulator.
        deal(Balancer.BAL, address(accumulator), 1_000_000e18);

        snapshotGaugeBalance = ERC20(Balancer.BAL).balanceOf(address(liquidityGauge));

        sizeDelegation = veBoost.received_balance(BAL.LOCKER);
        sizeLocker = veBoost.balanceOf(BAL.LOCKER) - sizeDelegation;

        bpsDelegated = (sizeDelegation * 1e18 / sizeLocker);
        expectedDelegation = 1_000_000e18 * bpsDelegated / 1e18;

        /// Apply the multiplier.
        expectedDelegation = expectedDelegation * 9e17 / 1e18;

        /// Notify the reward.
        accumulator.notifyReward(Balancer.BAL, false, false);

        assertEq(ERC20(Balancer.BAL).balanceOf(address(veBoostDelegation)), expectedDelegation);
        assertEq(
            ERC20(Balancer.BAL).balanceOf(address(liquidityGauge)),
            snapshotGaugeBalance + 1_000_000e18 - expectedDelegation
        );
    }
}
