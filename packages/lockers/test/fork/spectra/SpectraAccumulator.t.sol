// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SpectraProtocol} from "address-book/src/SpectraBase.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ISpectraRewardsDistributor} from "src/common/interfaces/spectra/spectra/ISpectraRewardsDistributor.sol";
import {ISdSpectraDepositor} from "src/common/interfaces/spectra/stakedao/ISdSpectraDepositor.sol";
import {BaseSpectraTokenTest} from "test/fork/spectra/common/BaseSpectraTokenTest.sol";

contract SpectraAccumulatorTest is BaseSpectraTokenTest {
    ISdSpectraDepositor internal spectraDepositor;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal initializer = makeAddr("initializer");

    ISpectraRewardsDistributor internal rewardsDistributor = ISpectraRewardsDistributor(SpectraProtocol.FEE_DISTRIBUTOR);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), 28026639);
        _deploySpectraIntegration();

        spectraDepositor = ISdSpectraDepositor(address(depositor));

        // Initialize locker
        deal(address(spectraToken), address(initializer), 1 ether);

        _initializeLocker();
    }

    /////////////////////////
    //  UTILITY FUNCTIONS
    ////////////////////////

    function _initializeLocker() public {
        vm.startPrank(initializer);
        spectraToken.approve(address(spectraDepositor), 1 ether);
        spectraDepositor.createLock(1 ether);
        vm.stopPrank();
    }

    /////////////////////////
    //  TEST FUNCTIONS
    ////////////////////////

    function test_cantDistributeWithoutSettingAccumulatorOnDepositor() public {
        vm.expectRevert(ISdSpectraDepositor.AccumulatorNotSet.selector);
        accumulator.claimAndNotifyAll();
    }

    function test_onlyGovernanceCanSetAccumulator() public {
        // Call with wrong address
        vm.prank(alice);
        vm.expectRevert(ISdSpectraDepositor.GOVERNANCE.selector);
        spectraDepositor.setAccumulator(address(accumulator));

        // Call with governance (deployer in this case, so address(this))
        spectraDepositor.setAccumulator(address(accumulator));

        // Check that the accumulator is correctly set
        assertEq(address(accumulator), spectraDepositor.accumulator());
    }

    function test_distributeRewardsFromAccumulator() public {
        spectraDepositor.setAccumulator(address(accumulator));

        // Deposit into the depositor to mint sdSPECTRA, these will be sent to accumulator to act as rewards
        uint256 rewardAmount = 1000 ether;

        deal(address(spectraToken), address(this), rewardAmount);
        spectraToken.approve(address(spectraDepositor), rewardAmount);
        spectraDepositor.deposit(rewardAmount, true, false, address(this));

        uint256 depositAmount = 10_000 ether;

        // Deposit into the deposit to have user on the gauge
        deal(address(spectraToken), alice, depositAmount);
        vm.startPrank(alice);
        spectraToken.approve(address(spectraDepositor), depositAmount);
        spectraDepositor.deposit(depositAmount, true, true, alice);
        vm.stopPrank();

        assertEq(ISdToken(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), depositAmount);

        // Transfer minted rewards to the accumulator
        IERC20(sdToken).transfer(address(accumulator), rewardAmount);

        // Call claim and notify all, should transfer to liquidity gauge
        accumulator.claimAndNotifyAll();

        // Rate should be the reward amount divided by seconds of a week
        assertEq(liquidityGauge.reward_data(sdToken).rate, rewardAmount / 1 weeks);

        skip(8 days);

        // Alice should claim all, so around the rate * seconds in a week (different calculation with integral on gauge)
        assertApproxEqRel(liquidityGauge.claimable_reward(alice, sdToken), (rewardAmount / 1 weeks) * (1 weeks), 1e15);
    }

    function test_distributeRewardsFromAccumulatorWithClaim() public {
        spectraDepositor.setAccumulator(address(accumulator));

        uint256 depositAmount = 1_000_000 ether;

        // Deposit into the deposit to have user on the gauge
        deal(address(spectraToken), alice, depositAmount);
        vm.startPrank(alice);
        spectraToken.approve(address(spectraDepositor), depositAmount);
        spectraDepositor.deposit(depositAmount, true, true, alice);
        vm.stopPrank();

        assertEq(ISdToken(sdToken).balanceOf(alice), 0);
        assertEq(liquidityGauge.balanceOf(alice), depositAmount);

        skip(2 weeks);

        // Simulate reward distribution from SPECTRA
        deal(address(spectraToken), address(this), 100_000 ether);
        spectraToken.transfer(address(rewardsDistributor), 100_000 ether);
        vm.prank(address(0xe59d75C87ED608E4f5F22c9f9AFFb7b6fd02cc7C));
        rewardsDistributor.checkpointToken();

        // Check that the locker has tokens to claim
        uint256 claimable = rewardsDistributor.claimable(ISdSpectraDepositor(address(depositor)).spectraLockedTokenId());
        assertGt(claimable, 0);

        // Store sdToken supply before claim
        uint256 sdTokenSupplyBefore = IERC20(sdToken).totalSupply();

        // Call claim and notify all, should rebase, mint and transfer to liquidity gauge
        accumulator.claimAndNotifyAll();

        // Check that the right amount is minted
        assertEq(IERC20(sdToken).totalSupply() - sdTokenSupplyBefore, claimable);

        // Check rate on the liquidity gauge
        // Rate should be the claimable amount divided by seconds of a week
        assertEq(liquidityGauge.reward_data(sdToken).rate, claimable / 1 weeks);
    }
}
