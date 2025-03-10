pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__addRewardToken is RewardVaultBaseTest {
    function test_RevertIfCallerIsNotAllowed() external {
        // it revert if caller is not allowed
    }

    function test_RevertIfRewardTokenAlreadyExists() external {
        // it revert if reward token already exists
    }

    function test_RevertIfMaxRewardTokenCountIsExceeded() external {
        // it revert if max reward token count is exceeded
    }

    function test_AddsTheRewardTokenToTheListOfRewardTokens() external {
        // it adds the reward token to the list of reward tokens
    }

    function test_AddTheRewardTokenToTheRewardMapping() external {
        // it add the reward token to the reward mapping
    }

    function test_InitializeTheRewardDataWithTheGivenDistibutorAndDefaultDuration() external {
        // it initialize the reward data with the given distibutor and default duration
    }

    function test_EmitsTheRewardTokenAddedEvent() external {
        // it emits the reward token added event
    }
}
