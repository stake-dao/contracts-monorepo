pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__getRewardsDuration is RewardVaultBaseTest {
    function test_ReturnsTheConstantRewardsDuration() external view {
        // it returns the constant rewards duration

        assertEq(rewardVault.getRewardsDuration(), rewardVault.DEFAULT_REWARDS_DURATION());
    }
}
