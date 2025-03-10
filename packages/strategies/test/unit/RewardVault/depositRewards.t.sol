pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__depositRewards is RewardVaultBaseTest {
    function test_UpdatesTheRewardForAllTokens() external {
        // it updates the reward for all tokens
    }

    function test_RevertIfCallerIsNotAuthorizedDistributor() external {
        // it revert if caller is not authorized distributor
    }

    function test_TransfersTheRewardsToTheSender() external {
        // it transfers the rewards to the sender
    }

    function test_RevertIfTheTransferReverts() external {
        // it revert if the transfer reverts
    }

    function test_CalculatesAndStoreTheNewRewardRate() external {
        // it calculates and store the new reward rate
    }

    function test_UpdatesTheTimeVariablesOfTheRewardData() external {
        // it updates the time variables of the reward data
    }

    function test_CalculatesAndUpdatesTheNewRewardPerTokenStored() external {
        // it calculates and updates the new reward per token stored
    }

    function test_EmitTheRewardDepositedEvent() external {
        // it emit the reward deposited event
    }
}
