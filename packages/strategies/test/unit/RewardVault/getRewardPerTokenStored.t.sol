pragma solidity 0.8.28;

import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__getRewardPerTokenStored is RewardVaultBaseTest {
    function test_ReturnsTheRewardPerTokenStoredForAGivenRewardToken(address token, uint32 rewardPerTokenStored)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the reward for a given reward token

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: 0,
            lastUpdateTime: 0,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: rewardPerTokenStored
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getRewardPerTokenStored(token), rewardPerTokenStored);
    }
}
