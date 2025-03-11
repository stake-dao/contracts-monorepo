pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Accountant} from "src/Accountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {Allocator} from "src/Allocator.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract RewardVault__deposit is RewardVaultBaseTest {
    function _deposit(uint256 assets, address receiver) internal virtual {
        rewardVault.deposit(assets, receiver);
    }

    function test_UpdatesTheRewardForTheReceiver(address receiver)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it updates the reward for the receiver

        address tokenToReward = makeAddr("tokenToReward");
        uint256 amount = 1e15;
        uint256 totalSupply = 10e18;
        uint256 existingBalance = 1e15;

        // create fake reward data
        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));
        RewardVault.RewardData memory rewardData = RewardVault.RewardData({
            rewardsDistributor: makeAddr("distributor"),
            rewardsDuration: 14 days,
            lastUpdateTime: uint32(block.timestamp),
            periodFinish: uint32(block.timestamp + 14 days),
            rewardRate: 1e12,
            rewardPerTokenStored: 1e12
        });
        address[] memory tokens = new address[](1);
        tokens[0] = tokenToReward;
        rewardVaultHarness._cheat_override_reward_tokens(tokens);
        rewardVaultHarness._cheat_override_reward_data(tokenToReward, rewardData);

        // warp the time to a date where the reward is updated
        vm.warp(block.timestamp + 10 days);

        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(totalSupply)
        );
        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.balanceOf.selector), abi.encode(existingBalance)
        );
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.allocator.selector),
            abi.encode(makeAddr("allocator"))
        );
        vm.mockCall(
            makeAddr("allocator"),
            abi.encodeWithSelector(Allocator.getDepositAllocation.selector),
            abi.encode(
                IAllocator.Allocation({
                    gauge: address(0),
                    harvested: false,
                    targets: new address[](0),
                    amounts: new uint256[](0)
                })
            )
        );
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.strategy.selector),
            abi.encode(makeAddr("strategy"))
        );
        vm.mockCall(
            makeAddr("strategy"),
            abi.encodeWithSelector(IStrategy.deposit.selector),
            abi.encode(IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}))
        );

        uint128 beforeRewardPerTokenStored = rewardVaultHarness.getRewardPerTokenStored(tokenToReward);
        uint32 lastUpdateTime = rewardVaultHarness.getLastUpdateTime(tokenToReward);
        uint128 beforeRewardPerTokenPaid = rewardVaultHarness.getRewardPerTokenPaid(receiver, tokenToReward);
        uint128 beforeClaimable = rewardVaultHarness.getClaimable(receiver, tokenToReward);

        _deposit(amount, receiver);

        assertLt(beforeRewardPerTokenStored, rewardVaultHarness.getRewardPerTokenStored(tokenToReward));
        assertLt(lastUpdateTime, rewardVaultHarness.getLastUpdateTime(tokenToReward));
        // TODO:
        // assertNotEq(0, rewardVaultHarness.getRewardPerTokenPaid(receiver, tokenToReward));
        // assertNotEq(0, rewardVaultHarness.getClaimable(receiver, tokenToReward));
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
