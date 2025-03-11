pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Accountant} from "src/Accountant.sol";

contract RewardVault__earned is RewardVaultBaseTest {
    function test_ReturnsTheEarnedRewardAndClaimableAmountForAGivenAccount(address account, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the earned reward and claimable amount for a given account

        // assume the account is not the zero address, and set some constants for the test
        vm.assume(account != address(0));

        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 10 days;
        uint128 claimable = 1e18 * 5; // 20%

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

        // Put the account in a state with no rewards paid out and no rewards available to claim
        rewardVaultHarness._cheat_override_account_data(
            account,
            tokens[0],
            RewardVault.AccountData({
                // Total rewards paid out to the account since the last update.
                rewardPerTokenPaid: 0,
                // Total rewards currently available for the account to claim,
                // based on the difference between rewardPerToken and rewardPerTokenPaid.
                claimable: claimable
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

        // the returned value is greater than the claimable amount because:
        // - The rewardPerTokenStored is greater than the rewardPerTokenPaid
        // - The balance is not zero
        assertGt(rewardVaultHarness.earned(account, token), claimable);
    }

    function test_ReturnsZeroForIncorrectToken(address account, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it revert if the token is not held by the accountant

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(0));

        // mock the balance of the account to return 5% of the total supply
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), account),
            abi.encode(0)
        );

        assertEq(rewardVaultHarness.earned(account, token), 0);
    }

    function test_ReturnsZeroForIncorrectAccount(address account, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns zero for incorrect account

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
        // mock the balance of the account to return 5% of the total supply
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), account),
            abi.encode(0)
        );

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);
        // update the reward for the account
        assertEq(rewardVaultHarness.earned(account, token), 0);
    }

    function test_ReturnsZeroWhenTheBalanceIsZero(address account, address token)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns zero when the balance is zero

        // assume the account is not the zero address, and set some constants for the test
        vm.assume(account != address(0));
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
        // mock the balance of the account to return 0
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), account),
            abi.encode(0) // THIS IS WHAT IT IS TESTED
        );

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);
        // update the reward for the account
        assertEq(rewardVaultHarness.earned(account, token), 0);
    }

    function test_ReturnsTheClaimableWhenThereIsNoEarning(address account, address token, uint128 claimable)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it returns the claimable when there is no earning

        // assume the account is not the zero address, and set some constants for the test
        vm.assume(account != address(0));
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

        // Put the account in a state with no rewards paid out and no rewards available to claim
        rewardVaultHarness._cheat_override_account_data(
            account,
            tokens[0],
            RewardVault.AccountData({
                // SAME rewardPerToken than the token. This is what it is tested
                rewardPerTokenPaid: uint128(TOTAL_SUPPLY / 5),
                claimable: claimable
            })
        );

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(TOTAL_SUPPLY)
        );
        // mock the balance of the account to something valid
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), account),
            abi.encode(TOTAL_SUPPLY / 20)
        );

        // The returned value is the claimable amount because:
        // - The rewardPerTokenPaid is the same as the rewardPerTokenStored
        // - The balance is not zero
        // - We are on the same block.number than the last update
        assertEq(rewardVaultHarness.earned(account, token), claimable);
    }
}
