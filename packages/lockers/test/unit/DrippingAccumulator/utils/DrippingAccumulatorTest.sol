// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.19 <0.9.0;

import {DrippingAccumulator} from "src/common/accumulator/DrippingAccumulator.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {Test} from "forge-std/src/Test.sol";
import {DrippingAccumulatorHarness} from "test/unit/DrippingAccumulator/utils/DrippingAccumulatorHarness.sol";

contract DrippingAccumulatorTest is Test {
    DrippingAccumulatorHarness internal accumulator;
    MockERC20 internal rewardToken;
    uint256 internal periodLength;

    function setUp() external {
        // deploy the reward token
        rewardToken = new MockERC20();
        rewardToken.initialize("Wrapped Ether ", "WETH", 18);

        // set the period length
        periodLength = 4;

        // deploy the accumulator
        accumulator = new DrippingAccumulatorHarness(
            makeAddr("gauge"), address(rewardToken), makeAddr("locker"), makeAddr("governance"), periodLength
        );
    }

    function _cheat_consumeAllSteps() internal {
        // fetch the initial parameters of the distribution
        (, uint120 nextStepTimestamp, uint16 remainingSteps) = accumulator.distribution();

        // consumes all the steps of the distribution by warping
        do {
            accumulator._expose_advanceDistributionStep();

            // fetch the new parameters of the distribution
            (, nextStepTimestamp, remainingSteps) = accumulator.distribution();
            vm.warp(nextStepTimestamp);
        } while (remainingSteps > 0);
    }

    function _cheat_startDistribution() internal {
        // warp to a valid timestamp
        vm.warp(1_111_111_111);

        // airdrop some reward tokens to the accumulator
        deal(address(rewardToken), address(accumulator), 100 ether);

        // start the distribution
        accumulator._expose_startNewDistribution();
    }
}
