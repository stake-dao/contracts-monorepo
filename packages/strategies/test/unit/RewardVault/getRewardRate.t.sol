pragma solidity 0.8.28;

import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__getRewardRate is RewardVaultBaseTest {
    function test_ReturnsTheRewardRateForAGivenRewardToken(address token, uint32 rewardRate)
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
            rewardRate: rewardRate,
            rewardPerTokenStored: 0
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getRewardRate(token), rewardRate);
    }
}
