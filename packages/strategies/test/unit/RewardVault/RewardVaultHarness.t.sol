pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RewardVault} from "src/RewardVault.sol";

// Exposes the useful internal functions of the RewardVault contract for testing purposes
contract RewardVaultHarness is RewardVault, Test {
    constructor(bytes4 protocolId, address protocolController, address accountant, bool triggerHarvest)
        RewardVault(protocolId, protocolController, accountant, triggerHarvest)
    {}

    // Utility function for testing purposes only. This function bypasses the expected flow
    // to add reward tokens to the vault. For each address in the tokens array, it adds the address
    // to the`rewardTokens` array and sets a mocked (but plausible) `rewardData`.
    function _cheat_override_reward_tokens(address[] calldata tokens) external {
        RewardVault.RewardData memory mockedRewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            lastUpdateTime: uint32(block.timestamp),
            periodFinish: uint32(block.timestamp + 7 days),
            // number of rewards distributed per second
            rewardRate: 1e10,
            // total rewards accumulated per token since the last update, used as a baseline for calculating new rewards.
            rewardPerTokenStored: uint128(1e20)
        });

        for (uint256 i; i < tokens.length; i++) {
            rewardTokens.push(tokens[i]);
            rewardData[tokens[i]] = mockedRewardData;
        }
    }

    // Utility function for testing purposes only. This function bypasses the expected flow
    // to add reward tokens to the vault. This function adds the reward token to the
    // `rewardTokens` array and sets the given rewardData for the address.
    function _cheat_override_reward_data(address rewardToken, RewardVault.RewardData calldata _rewardData) public {
        rewardTokens.push(rewardToken);
        rewardData[rewardToken] = _rewardData;
    }

    // Utility function for testing purposes only. This function bypasses the expected flow
    // to associated account data to the given token.
    function _cheat_override_account_data(
        address account,
        address rewardToken,
        RewardVault.AccountData calldata _accountData
    ) external {
        accountData[account][rewardToken] = _accountData;
    }
}
