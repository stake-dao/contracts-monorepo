// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DrippingAccumulator} from "src/common/accumulator/DrippingAccumulator.sol";
import {DrippingAccumulatorTest} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorTest.sol";

contract DrippingAccumulator__startNewDistribution is DrippingAccumulatorTest {
    function test_RevertsIfTheDistributionIsStillOngoing() external {
        // it reverts if the distribution is still ongoing

        // airdrop some reward tokens to the accumulator
        deal(address(rewardToken), address(accumulator), 100 ether);

        // start the first distribution
        accumulator._expose_startNewDistribution();

        // try starting a new distribution
        vm.expectRevert(DrippingAccumulator.DISTRIBUTION_NOT_OVER.selector);
        accumulator._expose_startNewDistribution();
    }

    function test_RevertsIfThereIsNoBalanceToDistributeForTheNewDistribution() external {
        // it reverts if there is no balance to distribute for the new distribution

        // try to start a new distribution
        vm.expectRevert(DrippingAccumulator.NO_REWARDS_TO_DISTRIBUTE.selector);
        accumulator._expose_startNewDistribution();
    }

    function test_EmitsAnEvent() external {
        // it emits an event

        // warp to a future timestamp (2025-05-06 11:19:23)
        vm.warp(1746530363);
        uint256 currentWeekTimestamp = accumulator._expose_getCurrentWeekTimestamp();

        // airdrop some reward tokens to the accumulator
        deal(address(rewardToken), address(accumulator), 100 ether);

        // start the distribution
        vm.expectEmit();
        emit DistributionStarted(currentWeekTimestamp, periodLength);
        accumulator._expose_startNewDistribution();
    }

    function test_StartsANewDistributionWithTheCorrectParameters(uint256 randomTimestamp) external {
        // it starts a new distribution with the correct parameters

        // warp to a random timestamp in the acceptable range
        randomTimestamp = bound(randomTimestamp, 0, type(uint120).max);
        vm.warp(randomTimestamp);
        uint256 currentWeekTimestamp = accumulator._expose_getCurrentWeekTimestamp();

        // airdrop some reward tokens to the accumulator
        deal(address(rewardToken), address(accumulator), 100 ether);

        // start the distribution
        accumulator._expose_startNewDistribution();

        // check the initial parameters of the distribution
        (uint120 timestamp, uint120 nextStepTimestamp, uint16 remainingSteps) = accumulator.distribution();
        assertEq(timestamp, currentWeekTimestamp);
        assertEq(nextStepTimestamp, currentWeekTimestamp);
        assertEq(remainingSteps, periodLength);
    }

    /// @notice Emitted when a new distribution starts.
    event DistributionStarted(uint256 timestamp, uint256 periodLength);
}
