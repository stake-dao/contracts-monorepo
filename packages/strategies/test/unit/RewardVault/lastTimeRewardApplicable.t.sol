pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RewardVault__lastTimeRewardApplicable is RewardVaultBaseTest {
    function test_WhenBlockTimestampIsLowerThanRewardPeriodFinish(uint256 blockTimestamp, uint32 periodFinish)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns block timestamp

        vm.assume(blockTimestamp < periodFinish);

        // create fake reward data for testing purposes
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));
        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            periodFinish: periodFinish,
            rewardsDuration: 0,
            lastUpdateTime: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });
        rewardVaultHarness._cheat_override_reward_data(makeAddr("token"), rewardData);

        // warp the block timestamp
        vm.warp(blockTimestamp);

        // assert that the last time reward applicable is the block timestamp
        assertEq(rewardVaultHarness.lastTimeRewardApplicable(makeAddr("token")), blockTimestamp);
    }

    function test_WhenRewardPeriodFinishIsLowerThanBlockTimestamp(uint256 blockTimestamp, uint32 periodFinish)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns reward periodFinish

        vm.assume(periodFinish < blockTimestamp);

        // create fake reward data for testing purposes
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));
        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            periodFinish: periodFinish,
            rewardsDuration: 0,
            lastUpdateTime: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });
        rewardVaultHarness._cheat_override_reward_data(makeAddr("token"), rewardData);

        // warp the block timestamp
        vm.warp(blockTimestamp);

        // assert that the last time reward applicable is the reward period finish
        assertEq(rewardVaultHarness.lastTimeRewardApplicable(makeAddr("token")), periodFinish);
    }
}
