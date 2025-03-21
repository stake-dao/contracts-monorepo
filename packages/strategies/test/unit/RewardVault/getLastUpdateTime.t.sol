pragma solidity 0.8.28;

import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__getLastUpdateTime is RewardVaultBaseTest {
    function test_ReturnsTheLastUpdateTimeForAGivenRewardToken(address token, uint32 lastUpdateTime)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the last update time for a given reward token

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: 0,
            lastUpdateTime: lastUpdateTime,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getLastUpdateTime(token), lastUpdateTime);
    }
}
