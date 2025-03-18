pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RewardVault__getRewardForDuration is RewardVaultBaseTest {
    function test_ReturnsTheRewardForAGivenRewardToken(address token, uint32 rewardsDuration)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the reward for a given reward token

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: rewardsDuration,
            lastUpdateTime: 0,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getRewardsDuration(token), rewardsDuration);
    }
}
