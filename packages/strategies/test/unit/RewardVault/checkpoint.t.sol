pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__updateReward is RewardVaultBaseTest {
    function test_UpdatesTheRewardForAGivenAccount(address account, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for a given account

        // assume the account is not the zero address, and set some constants for the test
        vm.assume(account != address(0));
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 7 days;

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            lastUpdateTime: uint32(block.timestamp), // current timestamp before wrapping
            periodFinish: uint32(block.timestamp + CAMPAIGN_DURATION),
            // number of rewards distributed per second
            rewardRate: 1e10,
            // total rewards accumulated per token since the last update, used as a baseline for calculating new rewards.
            rewardPerTokenStored: uint128(TOTAL_SUPPLY / 5)
        });
        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        // Put the account in a state with no rewards paid out and no rewards available to claim
        rewardVaultHarness._cheat_override_account_data(
            account,
            tokens[0],
            RewardVault.AccountData({
                // Total rewards paid out to the account since the last update.
                rewardPerTokenPaid: 0,
                // Total rewards currently available for the account to claim,
                // based on the difference between rewardPerToken and rewardPerTokenPaid.
                claimable: 0
            })
        );

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(TOTAL_SUPPLY)
        );
        // mock the balance of the account to return 5% of the total supply
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), account),
            abi.encode(TOTAL_SUPPLY / 20) // 5% of the total supply
        );

        // snapshot some values for future assertions
        uint128 beforeRewardPerTokenStored = rewardVaultHarness.getRewardPerTokenStored(token);
        uint128 beforeClaimable = rewardVaultHarness.getClaimable(token, account);

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);
        // update the reward for the account
        rewardVaultHarness.checkpoint(account);

        // assert the reward per token stored is updated
        assertEq(beforeRewardPerTokenStored, rewardVaultHarness.getRewardPerTokenStored(token));
        // assert the timestamp of the vault is updated to the current block timestamp
        assertEq(rewardVaultHarness.getLastUpdateTime(token), block.timestamp);
        // assert the reward per token variable in the account is updated with the value of the vault
        assertEq(
            rewardVaultHarness.getRewardPerTokenStored(token), rewardVaultHarness.getRewardPerTokenPaid(token, account)
        );
        // assert there are new rewards to claim for the account
        assertGt(rewardVaultHarness.getClaimable(token, account), beforeClaimable);
    }
}
