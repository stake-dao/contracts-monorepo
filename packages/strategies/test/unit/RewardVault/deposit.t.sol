pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__deposit is RewardVaultBaseTest {
    function test_UpdatesTheRewardForTheReceiver() external {
        // it updates the reward for the receiver
    }

    function test_WhenTheAllocatorAllocatesAllTheFundsToTheLocker() external {
        // it transfer all the ERC20 tokens to the locker
    }

    function test_WhenTheAllocatorAllocatesAllTheFundsToConvex() external {
        // it transfer all the ERC20 tokens to convex
    }

    function test_WhenTheAllocatorMixesTheAllocation() external {
        // it transfer the tokens based on the returned allocation repartition
    }

    function test_DepositTheFullAllocationToTheStrategy() external {
        // it deposit the full allocation to the strategy
    }

    function test_GivenZeroAddressReceiver() external {
        // it mints the shares to the sender
    }

    function test_GivenAnAddressReceiver() external {
        // it mints the shares to the receiver
    }

    function test_RevertsIfCallingAccountantCheckpointReverts() external {
        // it reverts if calling accountant checkpoint reverts
    }

    function test_RevertsIfTheDepositToTheStrategyReverts() external {
        // it reverts if the deposit to the strategy reverts
    }

    function test_RevertsIfOneOfTheERC20TransferReverts() external {
        // it reverts if one of the ERC20 transfer reverts
    }

    function test_EmitsTheDepositEvent() external {
        // it emits the deposit event
    }

    function test_ReturnsTheAmountOfAssetsDeposited() external {
        // it returns the amount of assets deposited
    }
}
