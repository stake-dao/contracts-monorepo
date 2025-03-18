pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RewardVault__getPeriodFinish is RewardVaultBaseTest {
    function test_ReturnsThePeriodFinishTimeForAGivenRewardToken(address token, uint32 periodFinish)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the period finish time for a given reward token

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: 0,
            lastUpdateTime: 0,
            periodFinish: periodFinish,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });

        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        assertEq(rewardVaultHarness.getPeriodFinish(token), periodFinish);
    }
}
