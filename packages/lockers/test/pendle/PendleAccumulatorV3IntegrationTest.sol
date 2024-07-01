// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "src/pendle/accumulator/PendleAccumulatorV3.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

import "src/base/fee/TreasuryRecipient.sol";
import "src/base/fee/LiquidityFeeRecipient.sol";
import "src/pendle/voters-rewards/VotersRewardsRecipient.sol";

contract PendleAccumulatorV3IntegrationTest is Test {
    uint256 blockNumber = 20_031_924;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal locker = PENDLE.LOCKER;
    address internal sdPendle = PENDLE.SDTOKEN;
    address internal vePENDLE = Pendle.VEPENDLE;

    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(PENDLE.GAUGE);

    PendleAccumulatorV3 internal accumulator;
    TreasuryRecipient internal treasuryRecipient;
    LiquidityFeeRecipient internal liquidityFeeRecipient;
    VotersRewardsRecipient internal votersRewardsRecipient;

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

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(forkId);

        /// Deploy Accumulator Contract.
        accumulator = new PendleAccumulatorV3(address(liquidityGauge), locker, address(this));

        /// Deploy Fees Recipients.
        treasuryRecipient = new TreasuryRecipient(address(this));
        liquidityFeeRecipient = new LiquidityFeeRecipient(address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 1000; // 5% to liquidity

        /// Set Fee split.
        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);

        /// Transfer voter rewards.
        votersRewardsRecipient = new VotersRewardsRecipient(address(this));
        accumulator.setTransferVotersRewards(true);
        accumulator.setVotesRewardRecipient(address(votersRewardsRecipient));

        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.set_reward_distributor(address(WETH), address(accumulator));
        liquidityGauge.set_reward_distributor(address(PENDLE.TOKEN), address(accumulator));
        vm.stopPrank();
    }

    function test_setup() public view {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(WETH));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(PENDLE.TOKEN));
        assertEq(rewardData.distributor, address(accumulator));

        assertEq(accumulator.transferVotersRewards(), true);
        assertEq(accumulator.votesRewardRecipient(), address(votersRewardsRecipient));

        PendleAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 500);
        assertEq(split.fees[1], 1000);
    }

    function test_claimAll(bool _setTransfer) public {
        //Check Dao recipient
        assertEq(WETH.balanceOf(address(treasuryRecipient)), 0);
        //// Check Bounty recipient
        assertEq(WETH.balanceOf(address(liquidityFeeRecipient)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

        address[] memory _poolsCopy = _pools;

        /// Remove 1 pool from the list to trigger NOT_CLAIMED_ALL.
        _pools.pop();

        vm.expectRevert(PendleAccumulatorV3.NOT_CLAIMED_ALL.selector);
        accumulator.claimAndNotifyAll(_pools, false, false, false);

        accumulator.setTransferVotersRewards(_setTransfer);
        accumulator.claimAndNotifyAll(_poolsCopy, false, false, false);

        uint256 treasury = WETH.balanceOf(address(treasuryRecipient));
        uint256 voters = WETH.balanceOf(address(votersRewardsRecipient));
        uint256 liquidityFee = WETH.balanceOf(address(liquidityFeeRecipient));
        uint256 gauge = WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimer = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to gauge.
        uint256 remaining = WETH.balanceOf(address(accumulator));
        uint256 total = treasury + liquidityFee + gauge + claimer + remaining + voters;

        PendleAccumulatorV3.Split memory feeSplit = accumulator.getFeeSplit();

        assertEq(total * accumulator.claimerFee() / 10_000, claimer);

        assertEq(total * feeSplit.fees[0] / 10_000, treasury);
        assertEq(total * feeSplit.fees[1] / 10_000, liquidityFee);

        assertEq(accumulator.remainingPeriods(), 3);

        if (!_setTransfer) {
            assertEq(voters, 0);
        }

        vm.expectRevert(PendleAccumulatorV3.ONGOING_REWARD.selector);
        accumulator.notifyReward(address(WETH), false, false);

        vm.expectRevert(PendleAccumulatorV3.NO_BALANCE.selector);
        accumulator.claimAndNotifyAll(_pools, false, false, false);

        skip(1 weeks);

        vm.expectRevert(PendleAccumulatorV3.NO_BALANCE.selector);
        accumulator.claimAndNotifyAll(_pools, false, false, false);

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

    function test_setters() public {
        accumulator.setTransferVotersRewards(false);
        assertEq(accumulator.transferVotersRewards(), false);

        accumulator.setVotesRewardRecipient(address(1));
        assertEq(accumulator.votesRewardRecipient(), address(1));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 100; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 50; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        PendleAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 100);
        assertEq(split.fees[1], 50);

        accumulator.setClaimerFee(1000);
        assertEq(accumulator.claimerFee(), 1000);

        accumulator.setPeriodsToAdd(10);
        assertEq(accumulator.periodsToAdd(), 10);

        accumulator.setFeeReceiver(address(1));
        assertEq(accumulator.feeReceiver(), address(1));

        vm.prank(address(2));
        vm.expectRevert(AccumulatorV2.GOVERNANCE.selector);
        accumulator.setFeeReceiver(address(2));
    }
}
