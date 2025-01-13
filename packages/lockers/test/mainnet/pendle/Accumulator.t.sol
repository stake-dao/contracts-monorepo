// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "src/mainnet/pendle/Accumulator.sol";
import "test/common/BaseAccumulatorTest.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor()
        BaseAccumulatorTest(
            20_031_924,
            "mainnet",
            PENDLE.LOCKER,
            PENDLE.SDTOKEN,
            Pendle.VEPENDLE,
            PENDLE.GAUGE,
            address(WETH),
            PENDLE.TOKEN
        )
    {}

    function _deployAccumulator() internal override returns (address payable accumulator) {
        accumulator = payable(new Accumulator(address(liquidityGauge), locker, address(this)));

        /// Set up the accumulator in the locker.
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));
    }

    /// Pools where rewards accrued at the block number 20_031_924.
    address[] public _pools = [
        0x4f30A9D41B80ecC5B94306AB4364951AE3170210, // VePendle
        0x107a2e3cD2BB9a32B9eE2E4d51143149F8367eBa,
        0x90c98ab215498B72Abfec04c651e2e496bA364C0,
        0xd7E0809998693fD87E81D51dE1619fd0EE658031,
        0x2Dfaf9a5E4F293BceedE49f2dBa29aACDD88E0C4,
        0x5E03C94Fc5Fb2E21882000A96Df0b63d2c4312e2,
        0x6Ae79089b2CF4be441480801bb741A531d94312b,
        0x952083cde7aaa11AB8449057F7de23A970AA8472,
        0x7dc07C575A0c512422dCab82CE9Ed74dB58Be30C
    ];

    function test_claimAll() public override {
        Accumulator accumulator = Accumulator(payable(accumulator));
        accumulator.setVotesRewardRecipient(PENDLE.VOTERS_REWARDS_RECIPIENT);

        uint256 id = vm.snapshot();
        _testWithTransferAt(accumulator, true);
        vm.revertTo(id);
        _testWithTransferAt(accumulator, false);
    }

    function _testWithTransferAt(Accumulator accumulator, bool _transfer) internal {
        //Check Dao recipient
        assertEq(WETH.balanceOf(address(treasuryRecipient)), 0);
        //// Check Bounty recipient
        assertEq(WETH.balanceOf(address(liquidityFeeRecipient)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

        address[] memory _poolsCopy = _pools;

        /// Remove 1 pool from the list to trigger NOT_CLAIMED_ALL.
        _pools.pop();

        vm.expectRevert(Accumulator.NOT_CLAIMED_ALL.selector);
        accumulator.claimAndNotifyAll(_pools, false, false);

        accumulator.setTransferVotersRewards(_transfer);
        accumulator.claimAndNotifyAll(_poolsCopy, false, false);

        uint256 treasury = WETH.balanceOf(address(treasuryRecipient));
        uint256 voters = WETH.balanceOf(address(PENDLE.VOTERS_REWARDS_RECIPIENT));
        uint256 liquidityFee = WETH.balanceOf(address(liquidityFeeRecipient));
        uint256 gauge = WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimer = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to gauge.
        uint256 remaining = WETH.balanceOf(address(accumulator));
        uint256 total = treasury + liquidityFee + gauge + claimer + remaining + voters;

        Accumulator.Split memory feeSplit = accumulator.getFeeSplit();
        assertEq(total * accumulator.claimerFee() / 1e18, claimer);

        assertEq(total * feeSplit.fees[0] / 1e18, treasury);
        assertEq(total * feeSplit.fees[1] / 1e18, liquidityFee);

        assertEq(accumulator.remainingPeriods(), 3);

        if (!_transfer) {
            assertEq(voters, 0);
        }

        vm.expectRevert(Accumulator.ONGOING_REWARD.selector);
        accumulator.notifyReward(address(WETH), false, false);

        vm.expectRevert(Accumulator.NO_BALANCE.selector);
        accumulator.claimAndNotifyAll(_pools, false, false);

        skip(1 weeks);

        vm.expectRevert(Accumulator.NO_BALANCE.selector);
        accumulator.claimAndNotifyAll(_pools, false, false);

        uint256 toDistribute = WETH.balanceOf(address(accumulator)) / 3;
        accumulator.notifyReward(address(WETH), false, false);

        /// Balances should be the same as we already took fees.
        assertEq(WETH.balanceOf(address(treasuryRecipient)), treasury);
        assertEq(WETH.balanceOf(address(liquidityFeeRecipient)), liquidityFee);
        assertEq(WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore, gauge + toDistribute);
        assertEq(WETH.balanceOf(address(this)), claimer);

        assertEq(accumulator.remainingPeriods(), 2);

        uint256 _before = ERC20(PENDLE.TOKEN).balanceOf(address(liquidityGauge));

        deal(PENDLE.TOKEN, address(accumulator), 1_000_000e18);
        accumulator.notifyReward(address(PENDLE.TOKEN), false, false);

        /// It should distribute 1_000_000 PENDLE to LGV4, meaning no fees were taken.
        assertEq(ERC20(PENDLE.TOKEN).balanceOf(address(liquidityGauge)), _before + 1_000_000e18);
    }
}
