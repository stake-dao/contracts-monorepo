// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";
import {DelegableAccumulatorHarness} from "test/unit/DelegableAccumulator/utils/DelegableAccumulatorHarness.sol";

contract DelegableAccumulatorTest is BaseAccumulatorTest {
    DelegableAccumulatorHarness internal delegableAccumulator;

    MockERC20 internal token;
    MockERC20 internal veToken;
    MockVeBoost internal veBoost;

    address internal veBoostDelegation;
    uint256 internal multiplier;

    function setUp() public virtual override {
        super.setUp();

        // deploy the reward token
        token = new MockERC20();
        token.initialize("Stake DAO X", "sdX", 18);

        // deploy the veToken
        veToken = new MockERC20();
        veToken.initialize("Voting Escrow Stake DAO X", "vesdX", 18);

        // deploy the veBoost
        veBoost = new MockVeBoost();

        veBoostDelegation = makeAddr("veBoostDelegation");
        multiplier = 0;

        delegableAccumulator = new DelegableAccumulatorHarness(
            address(gauge),
            address(rewardToken),
            address(locker),
            governance,
            address(token),
            address(veToken),
            address(veBoost),
            veBoostDelegation,
            multiplier
        );
    }
}

contract MockVeBoost {
    function received_balance(address locker) external view returns (uint256) {}
}
