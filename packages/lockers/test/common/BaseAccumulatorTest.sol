// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "src/common/accumulator/BaseAccumulator.sol";

import {CommonBase} from "test/common/CommonBase.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

abstract contract BaseAccumulatorTest is CommonBase, Test {
    uint256 blockNumber;
    string chain;

    constructor(
        uint256 _blockNumber,
        string memory _chain,
        address _locker,
        address _sdToken,
        address _veToken,
        address _liquidityGauge,
        address _rewardToken,
        address _strategyRewardToken
    ) {
        blockNumber = _blockNumber;
        chain = _chain;
        locker = _locker;
        sdToken = _sdToken;
        veToken = _veToken;
        liquidityGauge = ILiquidityGauge(_liquidityGauge);

        rewardToken = ERC20(_rewardToken);
        strategyRewardToken = ERC20(_strategyRewardToken);
    }

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl(chain), blockNumber);
        vm.selectFork(forkId);

        /// Deploy BaseAccumulator Contract.
        accumulator = BaseAccumulator(_deployAccumulator());
        vm.prank(accumulator.governance());
        accumulator.transferGovernance(address(this));
        accumulator.acceptGovernance();

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitBps = new uint256[](2);

        feeSplitReceivers[0] = treasuryRecipient;
        feeSplitReceivers[1] = liquidityFeeRecipient;

        feeSplitBps[0] = 5e16;
        feeSplitBps[1] = 10e16;

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitBps);

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(rewardToken));

        vm.startPrank(liquidityGauge.admin());
        if (rewardData.distributor == address(0)) {
            liquidityGauge.add_reward(address(rewardToken), address(accumulator));
        } else {
            liquidityGauge.set_reward_distributor(address(rewardToken), address(accumulator));
        }

        if (rewardToken != strategyRewardToken) {
            rewardData = liquidityGauge.reward_data(address(strategyRewardToken));

            if (rewardData.distributor == address(0)) {
                liquidityGauge.add_reward(address(strategyRewardToken), address(accumulator));
            } else {
                liquidityGauge.set_reward_distributor(address(strategyRewardToken), address(accumulator));
            }
        }

        vm.stopPrank();
    }

    function _deployAccumulator() internal virtual returns (address payable) {}

    function test_setup() public view virtual {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(rewardToken));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(strategyRewardToken));
        assertEq(rewardData.distributor, address(accumulator));

        BaseAccumulator.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], treasuryRecipient);
        assertEq(split.receivers[1], liquidityFeeRecipient);

        assertEq(split.fees[0], 5e16); // 5%
        assertEq(split.fees[1], 10e16); // 10%
    }

    function test_claimAll() public virtual {
        //Check Claimer recipient
        deal(address(rewardToken), address(this), 0);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        //Check Dao recipient
        deal(address(rewardToken), address(treasuryRecipient), 0);
        assertEq(rewardToken.balanceOf(address(treasuryRecipient)), 0);
        //// Check Bounty recipient
        deal(address(rewardToken), address(liquidityFeeRecipient), 0);
        assertEq(rewardToken.balanceOf(address(liquidityFeeRecipient)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = rewardToken.balanceOf(address(liquidityGauge));

        accumulator.claimAndNotifyAll(false, false);

        uint256 treasury = rewardToken.balanceOf(address(treasuryRecipient));
        uint256 liquidityFee = rewardToken.balanceOf(address(liquidityFeeRecipient));
        uint256 gauge = rewardToken.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimer = rewardToken.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to gauge.
        uint256 remaining = rewardToken.balanceOf(address(accumulator));
        uint256 total = treasury + liquidityFee + gauge + claimer + remaining;

        BaseAccumulator.Split memory feeSplit = accumulator.getFeeSplit();

        assertEq(total * accumulator.claimerFee() / 1e18, claimer);

        assertEq(total * feeSplit.fees[0] / 1e18, treasury);
        assertEq(total * feeSplit.fees[1] / 1e18, liquidityFee);

        skip(1 weeks);

        uint256 _before = ERC20(strategyRewardToken).balanceOf(address(liquidityGauge));

        deal(address(strategyRewardToken), address(accumulator), 1_000e18);
        accumulator.notifyReward(address(strategyRewardToken), false, false);

        /// It should distribute 1_000_000 PENDLE to LGV4, meaning no fees were taken.
        if (rewardToken != strategyRewardToken) {
            assertEq(ERC20(strategyRewardToken).balanceOf(address(liquidityGauge)), _before + 1_000e18);
        } else {
            uint256 _treasuryFee = 1_000e18 * feeSplit.fees[0] / 1e18;
            uint256 _liquidityFee = 1_000e18 * feeSplit.fees[1] / 1e18;
            uint256 _claimerFee = 1_000e18 * accumulator.claimerFee() / 1e18;

            assertEq(ERC20(strategyRewardToken).balanceOf(address(treasuryRecipient)), treasury + _treasuryFee);
            assertEq(ERC20(strategyRewardToken).balanceOf(address(liquidityFeeRecipient)), liquidityFee + _liquidityFee);
            assertEq(
                ERC20(strategyRewardToken).balanceOf(address(liquidityGauge)),
                _before + 1_000e18 - _treasuryFee - _liquidityFee - _claimerFee
            );
        }
    }

    function test_setters() public {
        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 100; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 50; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        BaseAccumulator.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 100);
        assertEq(split.fees[1], 50);

        accumulator.setClaimerFee(1000e15);
        assertEq(accumulator.claimerFee(), 1000e15);

        accumulator.setFeeReceiver(address(1));
        assertEq(accumulator.feeReceiver(), address(1));

        vm.prank(address(2));
        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        accumulator.setFeeReceiver(address(2));
    }
}
