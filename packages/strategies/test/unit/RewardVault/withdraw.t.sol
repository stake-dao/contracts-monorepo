pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__withdraw is RewardVaultBaseTest {
    function test_GivenSenderIsNotOwner() external {
        // it reverts if the allowance is not enough
        // it update the allowance when it is finite
    }

    function test_UpdatesTheRewardForTheOwner() external {
        // it updates the reward for the owner
    }

    function test_TellsTheStrategyToWithdrawTheAssets() external {
        // it tells the strategy to withdraw the assets
    }

    function test_TellsTheAccoutantToBurnTheTokens() external {
        // it tells the accoutant to burn the tokens
    }

    function test_TransfersTheAssetsToTheReceiver() external {
        // it transfers the assets to the receiver
    }

    function test_EmitsAWithdrawEvent() external {
        // it emits a withdraw event
    }

    function test_ReturnsTheAmountOfSharesBurned() external {
        // it returns the amount of shares burned
    }
}
