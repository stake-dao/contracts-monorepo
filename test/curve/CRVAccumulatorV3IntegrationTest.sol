// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "src/curve/accumulator/CRVAccumulatorV3.sol";

import {IStrategy} from "lib/herdaddy/src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

contract CRVAccumulatorV3IntegrationTest is Test {
    uint256 blockNumber = 20_031_924;

    address public constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address internal locker = CRV.LOCKER;
    address internal sdToken = CRV.SDTOKEN;
    address internal veToken = Curve.VECRV;

    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(CRV.GAUGE);

    CRVAccumulatorV3 internal accumulator;
    address internal treasuryRecipient = DAO.TREASURY;
    address internal liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(forkId);

        /// Deploy Accumulator Contract.
        accumulator = new CRVAccumulatorV3(address(liquidityGauge), locker, address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = treasuryRecipient;
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = liquidityFeeRecipient;
        feeSplitFees[1] = 1000; // 5% to liquidity

        /// Set Fee split.
        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setAccumulator(address(accumulator));

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.add_reward(address(CRV_USD), address(accumulator));
        liquidityGauge.set_reward_distributor(address(CRV.TOKEN), address(accumulator));
        vm.stopPrank();
    }

    function test_setup() public {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(CRV_USD));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(CRV.TOKEN));
        assertEq(rewardData.distributor, address(accumulator));

        CRVAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 500);
        assertEq(split.fees[1], 1000);
    }

    // function test_claimAll(bool _setTransfer) public {
    // //Check Dao recipient
    // assertEq(WETH.balanceOf(address(treasuryRecipient)), 0);
    // //// Check Bounty recipient
    // assertEq(WETH.balanceOf(address(liquidityFeeRecipient)), 0);
    // //// Check lgv4
    // uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

    // address[] memory _poolsCopy = _pools;

    // /// Remove 1 pool from the list to trigger NOT_CLAIMED_ALL.
    // _pools.pop();

    // vm.expectRevert(PendleAccumulatorV3.NOT_CLAIMED_ALL.selector);
    // accumulator.claimAll(_pools, false, false, false);

    // accumulator.setTransferVotersRewards(_setTransfer);
    // accumulator.claimAll(_poolsCopy, false, false, false);

    // uint256 treasury = WETH.balanceOf(address(treasuryRecipient));
    // uint256 voters = WETH.balanceOf(address(votersRewardsRecipient));
    // uint256 liquidityFee = WETH.balanceOf(address(liquidityFeeRecipient));
    // uint256 gauge = WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
    // uint256 claimer = WETH.balanceOf(address(this));

    // /// WETH is distributed over 4 weeks to gauge.
    // uint256 remaining = WETH.balanceOf(address(accumulator));
    // uint256 total = treasury + liquidityFee + gauge + claimer + remaining + voters;

    // PendleAccumulatorV3.Split memory feeSplit = accumulator.getFeeSplit();

    // assertEq(total * accumulator.claimerFee() / 10_000, claimer);

    // assertEq(total * feeSplit.fees[0] / 10_000, treasury);
    // assertEq(total * feeSplit.fees[1] / 10_000, liquidityFee);

    // assertEq(accumulator.remainingPeriods(), 3);

    // if (!_setTransfer) {
    // assertEq(voters, 0);
    // }

    // vm.expectRevert(PendleAccumulatorV3.ONGOING_REWARD.selector);
    // accumulator.notifyReward(address(WETH), false, false);

    // vm.expectRevert(PendleAccumulatorV3.NO_BALANCE.selector);
    // accumulator.claimAll(_pools, false, false, false);

    // skip(1 weeks);

    // vm.expectRevert(PendleAccumulatorV3.NO_BALANCE.selector);
    // accumulator.claimAll(_pools, false, false, false);

    // uint256 toDistribute = WETH.balanceOf(address(accumulator)) / 3;
    // accumulator.notifyReward(address(WETH), false, false);

    // /// Balances should be the same as we already took fees.
    // assertEq(WETH.balanceOf(address(treasuryRecipient)), treasury);
    // assertEq(WETH.balanceOf(address(liquidityFeeRecipient)), liquidityFee);
    // assertEq(WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore, gauge + toDistribute);
    // assertEq(WETH.balanceOf(address(this)), claimer);

    // assertEq(accumulator.remainingPeriods(), 2);

    // uint256 _before = ERC20(PENDLE.TOKEN).balanceOf(address(liquidityGauge));

    // deal(PENDLE.TOKEN, address(accumulator), 1_000_000e18);
    // accumulator.notifyReward(address(PENDLE.TOKEN), false, false);

    // /// It should distribute 1_000_000 PENDLE to LGV4, meaning no fees were taken.
    // assertEq(ERC20(PENDLE.TOKEN).balanceOf(address(liquidityGauge)), _before + 1_000_000e18);
    // }

    function test_setters() public {
        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 100; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 50; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        CRVAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 100);
        assertEq(split.fees[1], 50);

        accumulator.setClaimerFee(1000);
        assertEq(accumulator.claimerFee(), 1000);

        accumulator.setFeeReceiver(address(1));
        assertEq(accumulator.feeReceiver(), address(1));

        vm.prank(address(2));
        vm.expectRevert(AccumulatorV2.GOVERNANCE.selector);
        accumulator.setFeeReceiver(address(2));
    }
}
