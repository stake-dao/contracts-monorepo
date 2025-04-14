pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Accountant} from "src/Accountant.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__depositRewards is RewardVaultBaseTest {
    function test_RevertIfCallerIsNotAuthorizedDistributor(address token, address expectedDistributor, address caller)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it revert if caller is not authorized distributor

        vm.assume(caller != expectedDistributor);
        vm.assume(expectedDistributor != address(0));

        // store a fake reward data for the token with the expected distributor
        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: expectedDistributor,
            lastUpdateTime: 0,
            periodFinish: 0,
            rewardRate: 0,
            rewardPerTokenStored: 0
        });
        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(1e20));

        // expect the deposit to revert with the UnauthorizedRewardsDistributor error because the caller is not the expected distributor
        vm.expectRevert(abi.encodeWithSelector(RewardVault.UnauthorizedRewardsDistributor.selector));
        vm.prank(caller);
        rewardVault.depositRewards(token, 1e18);
    }

    function test_RevertIfTheTransferReverts(address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it revert if the transfer reverts
        vm.assume(distributor != address(0));

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 7 days;
        uint256 DISTRIBUTOR_BALANCE = TOTAL_SUPPLY / 20; // 5% of the total supply
        address token = address(rewardToken);

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
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
        // mock the balance of the account to return 5% of the total supply ?:
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), distributor),
            abi.encode(DISTRIBUTOR_BALANCE)
        );

        // set the distributor balance and approve the reward vault to spend it
        deal(token, distributor, DISTRIBUTOR_BALANCE);
        vm.prank(distributor);
        rewardToken.approve(address(rewardVault), DISTRIBUTOR_BALANCE);

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);

        // mock the transfer to revert
        vm.mockCallRevert(
            address(rewardToken),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, distributor, address(rewardVault), uint128(DISTRIBUTOR_BALANCE)
            ),
            "UNEXPECTED_ERROR"
        );

        // expect the deposit to revert with the IERC20.safeTransferFrom.selector error
        vm.expectRevert("UNEXPECTED_ERROR");
        vm.prank(distributor);
        rewardVault.depositRewards(token, uint128(DISTRIBUTOR_BALANCE));
    }

    function test_UpdatesTheLastUpdateTimeAndRewardPerTokenStoredForAllTokens(address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for all tokens

        vm.assume(distributor != address(0));

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 7 days;
        uint256 DISTRIBUTOR_BALANCE = TOTAL_SUPPLY / 20; // 5% of the total supply
        address token = address(rewardToken);

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
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
        // mock the balance of the account to return 5% of the total supply ?:
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), distributor),
            abi.encode(DISTRIBUTOR_BALANCE)
        );

        // set the distributor balance and approve the reward vault to spend it
        deal(token, distributor, DISTRIBUTOR_BALANCE);
        vm.prank(distributor);
        rewardToken.approve(address(rewardVault), DISTRIBUTOR_BALANCE);

        // snapshot some values for future assertions
        uint128 beforeRewardPerTokenStored = rewardVaultHarness.getRewardPerTokenStored(token);

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);

        // make the distributor deposits the rewards
        vm.prank(distributor);
        rewardVaultHarness.depositRewards(token, uint128(DISTRIBUTOR_BALANCE));

        for (uint256 i; i < tokens.length; i++) {
            address _token = tokens[i];
            assertEq(rewardVaultHarness.getLastUpdateTime(_token), block.timestamp);
            assertEq(rewardVaultHarness.getRewardPerTokenStored(_token), beforeRewardPerTokenStored);
        }
    }

    function test_TransfersTheRewardsFromTheSenderToTheVault(address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it transfers the rewards from the sender to the vault

        vm.assume(distributor != address(0));
        _assumeUnlabeledAddress(distributor);

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 7 days;
        uint256 DISTRIBUTOR_BALANCE = TOTAL_SUPPLY / 20; // 5% of the total supply
        address token = address(rewardToken);

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
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
        // mock the balance of the account to return 5% of the total supply ?:
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), distributor),
            abi.encode(DISTRIBUTOR_BALANCE)
        );

        // set the distributor balance and approve the reward vault to spend it
        deal(token, distributor, DISTRIBUTOR_BALANCE);
        vm.prank(distributor);
        rewardToken.approve(address(rewardVault), DISTRIBUTOR_BALANCE);

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);

        // make the distributor deposits the rewards
        vm.prank(distributor);
        rewardVaultHarness.depositRewards(token, uint128(DISTRIBUTOR_BALANCE));

        assertEq(rewardToken.balanceOf(address(rewardVault)), DISTRIBUTOR_BALANCE);
        assertEq(rewardToken.balanceOf(distributor), 0);
    }

    function test_UpdatesTheRewardDataOfTheGivenToken(address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for all tokens

        vm.assume(distributor != address(0));

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint32 CAMPAIGN_DURATION = 7 days;
        uint256 DISTRIBUTOR_BALANCE = TOTAL_SUPPLY / 20; // 5% of the total supply
        address token = address(rewardToken);

        // generate plausible fake reward data for a vault
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);

        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
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
        // mock the balance of the account to return 5% of the total supply ?:
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), distributor),
            abi.encode(DISTRIBUTOR_BALANCE)
        );

        // set the distributor balance and approve the reward vault to spend it
        deal(token, distributor, DISTRIBUTOR_BALANCE);
        vm.prank(distributor);
        rewardToken.approve(address(rewardVault), DISTRIBUTOR_BALANCE);

        // snapshot some values for future assertions
        uint128 beforeRewardRate = rewardVaultHarness.getRewardRate(token);
        uint128 beforeRewardPerTokenStored = rewardVaultHarness.getRewardPerTokenStored(token);

        // move time forward to halfway through the campaign
        vm.warp(block.timestamp + CAMPAIGN_DURATION / 2);

        // make the distributor deposits the rewards
        vm.prank(distributor);
        rewardVaultHarness.depositRewards(token, uint128(DISTRIBUTOR_BALANCE));

        assertEq(rewardVaultHarness.getLastUpdateTime(token), block.timestamp);
        assertEq(rewardVaultHarness.getPeriodFinish(token), block.timestamp + CAMPAIGN_DURATION);
        assertGt(rewardVaultHarness.getRewardRate(token), beforeRewardRate);
        assertEq(rewardVaultHarness.getRewardPerTokenStored(token), beforeRewardPerTokenStored);
    }

    function test_EmitTheRewardDepositedEvent(address distributor)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it emit the reward deposited event

        vm.assume(distributor != address(0));

        // assume the account is not the zero address, and set some constants for the test
        uint256 TOTAL_SUPPLY = 1e18;
        uint256 DISTRIBUTOR_BALANCE = TOTAL_SUPPLY / 20; // 5% of the total supply
        address token = address(rewardToken);

        // generate plausible fake reward data for a vault
        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: distributor,
            lastUpdateTime: 1,
            periodFinish: 1,
            rewardRate: 1,
            rewardPerTokenStored: 1
        });
        rewardVaultHarness._cheat_override_reward_data(token, rewardData);

        // mock the total supply to return the expected value(calling the accountant.totalSupply() function)
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(TOTAL_SUPPLY)
        );
        // mock the balance of the account to return 5% of the total supply ?:
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(Accountant.balanceOf.selector, address(rewardVaultHarness), distributor),
            abi.encode(DISTRIBUTOR_BALANCE)
        );

        // set the distributor balance and approve the reward vault to spend it
        deal(token, distributor, DISTRIBUTOR_BALANCE);
        vm.prank(distributor);
        rewardToken.approve(address(rewardVault), DISTRIBUTOR_BALANCE);

        // expect the reward deposited event to be emitted
        vm.expectEmit(true, true, true, true, address(rewardToken));
        emit IERC20.Transfer(distributor, address(rewardVault), DISTRIBUTOR_BALANCE);

        // make the distributor deposits the rewards
        vm.prank(distributor);
        rewardVaultHarness.depositRewards(token, uint128(DISTRIBUTOR_BALANCE));
    }
}
