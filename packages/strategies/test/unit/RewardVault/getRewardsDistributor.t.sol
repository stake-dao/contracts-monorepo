pragma solidity 0.8.28;

import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__getRewardsDistributor is RewardVaultBaseTest {
    function test_ReturnsTheDistributorAddressForAGivenRewardToken(address token, address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the reward for a given reward token

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
            rewardsDuration: 0,
            lastUpdateTime: 0,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getRewardsDistributor(token), distributor);
    }
}
