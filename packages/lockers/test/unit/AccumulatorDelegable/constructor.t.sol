// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DelegableAccumulatorHarness} from "test/unit/AccumulatorDelegable/utils/DelegableAccumulatorHarness.sol";

contract DelegableAccumulator__constructor is Test {
    DelegableAccumulatorHarness internal accumulator;

    function setUp() public virtual {
        accumulator = new DelegableAccumulatorHarness(
            makeAddr("gauge"),
            makeAddr("rewardToken"),
            makeAddr("locker"),
            makeAddr("governance"),
            makeAddr("token"),
            makeAddr("veToken"),
            makeAddr("veBoost"),
            makeAddr("veBoostDelegation"),
            1000
        );
    }

    function test_SetsTheToken() external {
        // it sets the token

        assertEq(accumulator.token(), makeAddr("token"));
    }

    function test_SetsTheVeToken() external {
        // it sets the veToken

        assertEq(accumulator.veToken(), makeAddr("veToken"));
    }

    function test_SetsTheVeBoost() external {
        // it sets the veBoost

        assertEq(accumulator.veBoost(), makeAddr("veBoost"));
    }

    function test_SetsTheVeBoostDelegation() external {
        // it sets the veBoostDelegation

        assertEq(accumulator.veBoostDelegation(), makeAddr("veBoostDelegation"));
    }

    function test_SetsTheMultiplier() external view {
        // it sets the multiplier

        assertEq(accumulator.multiplier(), 1000);
    }
}
