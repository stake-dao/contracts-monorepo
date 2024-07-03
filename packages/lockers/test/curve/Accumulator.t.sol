// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "src/curve/accumulator/CRVAccumulator.sol";

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import "herdaddy/interfaces/stake-dao/IStrategy.sol";
import "herdaddy/interfaces/curve/IFeeDistributor.sol";

contract AccumulatorTest is Test {
    uint256 blockNumber = 20_169_332;

    ERC20 public constant CRV_USD = ERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    address public constant FEE_DISTRIBUTOR = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;

    address internal locker = CRV.LOCKER;
    address internal sdToken = CRV.SDTOKEN;
    address internal veToken = Curve.VECRV;

    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(CRV.GAUGE);

    CRVAccumulator internal accumulator;
    address internal treasuryRecipient = DAO.TREASURY;
    address internal liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(forkId);

        /// Deploy Accumulator Contract.
        accumulator = new CRVAccumulator(address(liquidityGauge), locker, address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = treasuryRecipient;
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = liquidityFeeRecipient;
        feeSplitFees[1] = 1000; // 5% to liquidity

        /// Set Fee split.
        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);

        /// Setup new Fee Distributor.

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setAccumulator(address(accumulator));

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setFeeDistributor(address(FEE_DISTRIBUTOR));

        vm.prank(DAO.GOVERNANCE);
        IStrategy(CRV.STRATEGY).setFeeRewardToken(address(CRV_USD));

        /// Simulate CRV_USD rewards.
        deal(address(CRV_USD), address(FEE_DISTRIBUTOR), 1_000_000e18);

        address _admin = IFeeDistributor(FEE_DISTRIBUTOR).admin();

        vm.prank(_admin);
        IFeeDistributor(FEE_DISTRIBUTOR).checkpoint_token();

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.add_reward(address(CRV_USD), address(accumulator));
        liquidityGauge.set_reward_distributor(address(CRV.TOKEN), address(accumulator));
        vm.stopPrank();

        skip(1 weeks);
    }

    function test_setup() public view {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(CRV_USD));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(CRV.TOKEN));
        assertEq(rewardData.distributor, address(accumulator));

        CRVAccumulator.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 500);
        assertEq(split.fees[1], 1000);
    }

    function test_claimAll(bool pullFromFeeReceiver) public {
        //Check Dao recipient
        assertEq(CRV_USD.balanceOf(address(treasuryRecipient)), 0);
        //// Check Bounty recipient
        assertEq(CRV_USD.balanceOf(address(liquidityFeeRecipient)), 0);

        assertEq(CRV_USD.balanceOf(address(FEE_DISTRIBUTOR)), 1_000_000e18);

        /// Check lgv4.
        uint256 gaugeBalanceBefore = CRV_USD.balanceOf(address(liquidityGauge));

        accumulator.claimAndNotifyAll(false, pullFromFeeReceiver, pullFromFeeReceiver);

        uint256 treasury = CRV_USD.balanceOf(address(treasuryRecipient));
        uint256 liquidityFee = CRV_USD.balanceOf(address(liquidityFeeRecipient));
        uint256 gauge = CRV_USD.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimer = CRV_USD.balanceOf(address(this));
        uint256 total = treasury + liquidityFee + gauge + claimer;

        assertGt(total, 0);

        CRVAccumulator.Split memory feeSplit = accumulator.getFeeSplit();
        assertEq(total * accumulator.claimerFee() / 10_000, claimer);
        assertEq(total * feeSplit.fees[0] / 10_000, treasury);
        assertEq(total * feeSplit.fees[1] / 10_000, liquidityFee);

        uint256 _before = ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge));

        deal(CRV.TOKEN, address(accumulator), 1_000_000e18);
        accumulator.notifyReward(address(CRV.TOKEN), false, false);

        /// It should distribute 1_000_000 CRV  LGV4, meaning no fees were taken.
        assertEq(ERC20(CRV.TOKEN).balanceOf(address(liquidityGauge)), _before + 1_000_000e18);

        _before = CRV_USD.balanceOf(address(liquidityGauge));

        deal(address(CRV_USD), address(accumulator), 1_000_000e18);
        accumulator.notifyReward(address(CRV_USD), false, false);

        /// Compute new fee split.
        feeSplit = accumulator.getFeeSplit();
        uint256 new_treasury = 1_000_000e18 * feeSplit.fees[0] / 10_000;
        uint256 new_liquidityFee = 1_000_000e18 * feeSplit.fees[1] / 10_000;
        uint256 new_claimer = 1_000_000e18 * accumulator.claimerFee() / 10_000;

        total = 1_000_000e18 - new_treasury - new_liquidityFee - new_claimer;

        assertEq(CRV_USD.balanceOf(address(treasuryRecipient)), treasury + new_treasury);
        assertEq(CRV_USD.balanceOf(address(liquidityFeeRecipient)), liquidityFee + new_liquidityFee);
        assertEq(CRV_USD.balanceOf(address(liquidityGauge)), _before + total);
        assertEq(CRV_USD.balanceOf(address(this)), claimer + new_claimer);
    }

    function test_setters() public {
        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 100; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 50; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        CRVAccumulator.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 100);
        assertEq(split.fees[1], 50);

        accumulator.setClaimerFee(1000);
        assertEq(accumulator.claimerFee(), 1000);

        accumulator.setFeeReceiver(address(1));
        assertEq(accumulator.feeReceiver(), address(1));

        vm.prank(address(2));
        vm.expectRevert(Accumulator.GOVERNANCE.selector);
        accumulator.setFeeReceiver(address(2));
    }
}
