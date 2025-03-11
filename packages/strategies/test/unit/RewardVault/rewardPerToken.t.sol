pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Accountant} from "src/Accountant.sol";

contract RewardVault__rewardPerToken is RewardVaultBaseTest {
    function test_ReturnsTheRewardPerTokenStoredWhenTotalSupplyIs0(uint128 rewardPerTokenStored, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the reward per token stored when total supply is 0

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: address(0),
            rewardsDuration: 0,
            lastUpdateTime: 0,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: rewardPerTokenStored
        });
        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        // mock the total supply to return 0
        vm.mockCall(address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(0));

        assertEq(rewardVaultHarness.rewardPerToken(token), rewardPerTokenStored);
    }

    function test_CalculatesTheRewardPerTokenBasedOnItsData(address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it calculates the reward per token based on its data

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 10 days;

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: CAMPAIGN_DURATION,
            lastUpdateTime: uint32(block.timestamp), // current timestamp before wrapping
            periodFinish: uint32(block.timestamp + CAMPAIGN_DURATION),
            // number of rewards distributed per second
            rewardRate: 1e10,
            // total rewards accumulated per token since the last update, used as a baseline for calculating new rewards.
            rewardPerTokenStored: uint128(TOTAL_SUPPLY / 5)
        });
        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(TOTAL_SUPPLY)
        );
        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);
        // update the reward for the account
        uint128 calculatedRewardPerToken = rewardVaultHarness.rewardPerToken(token);

        // assert the reward per token stored is updated
        assertLt(uint128(TOTAL_SUPPLY / 5), calculatedRewardPerToken);
    }
}
