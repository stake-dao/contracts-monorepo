pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault} from "src/RewardVault.sol";
import {BaseTest} from "test/Base.t.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract RewardReceiver__distributeRewards is BaseTest {
    RewardReceiver private rewardReceiver;
    address private rewardVault;
    address[5] private rewardTokens;

    function setUp() public override {
        // it returns the correct vault address

        super.setUp();

        // deploy fake reward tokens
        rewardTokens[0] = address(new ERC20Mock("Reward Token 1", "RT1", 18));
        rewardTokens[1] = address(new ERC20Mock("Reward Token 2", "RT2", 18));
        rewardTokens[2] = address(new ERC20Mock("Reward Token 3", "RT3", 18));
        rewardTokens[3] = address(new ERC20Mock("Reward Token 4", "RT4", 18));
        rewardTokens[4] = address(new ERC20Mock("Reward Token 5", "RT5", 18));

        // deploy a fake reward vault
        rewardVault = address(new FakeRewardVault());

        // deploy a RewardReceiver basic contrat and clone it with the immutable variables
        rewardReceiver =
            RewardReceiver(Clones.cloneWithImmutableArgs(address(new RewardReceiver()), abi.encodePacked(rewardVault)));
    }

    function test_RevertsIfThereIsNoRewardTokens() external {
        // it reverts if there is no reward tokens

        // mock the vault to return no reward tokens
        vm.mockCall(
            rewardVault, abi.encodeWithSelector(RewardVault.getRewardTokens.selector), abi.encode(new address[](0))
        );

        // expect the reward receiver contract to revert because there are no reward tokens
        vm.expectRevert(RewardReceiver.NoRewards.selector);
        rewardReceiver.distributeRewards();
    }

    function test_DoesNothingIfThereAreNoRewardsToDistribute(uint256 numberOfRewardTokens) external {
        // it does nothing if there are no rewards to distribute

        // generate a array of reward tokens
        numberOfRewardTokens = bound(numberOfRewardTokens, 1, 5);
        address[] memory tokens = new address[](numberOfRewardTokens);

        // for each reward token, mock the balance to be 0
        for (uint256 i; i < numberOfRewardTokens; i++) {
            tokens[i] = rewardTokens[i];

            // mock the reward token to have no balance
            vm.mockCall(tokens[i], abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
        }

        // mock the vault to return the reward tokens
        vm.mockCall(rewardVault, abi.encodeWithSelector(RewardVault.getRewardTokens.selector), abi.encode(tokens));

        // expect the reward receiver contract to do nothing
        rewardReceiver.distributeRewards();
    }

    function test_RevertsIfOneBalanceIsHigherThanUint128Max(uint256 numberOfRewardTokens, uint256 overflowIndex)
        external
    {
        // it reverts if one balance is higher than uint128 max

        // generate a array of reward tokens
        numberOfRewardTokens = bound(numberOfRewardTokens, 1, 5);
        address[] memory tokens = new address[](numberOfRewardTokens);

        // randomly draw which token will have the overflowed balance
        overflowIndex = bound(overflowIndex, 1, numberOfRewardTokens) - 1;

        // for each reward token, mock the balance to be 42 or the max + 1
        for (uint256 i; i < numberOfRewardTokens; i++) {
            tokens[i] = rewardTokens[i];
            address token = rewardTokens[i];

            // set the balance of the reward token. One of the balance in the array will cause an overflow
            uint256 balance = overflowIndex == i ? uint256(type(uint128).max) + 1 : 42;

            // "airdrop" the reward token to the reward receiver
            deal(token, address(rewardReceiver), balance);

            // mock the vault to have the reward receiver as the rewards distributor for the reward token
            vm.mockCall(
                address(rewardVault), abi.encodeWithSelector(RewardVault.getRewardsDistributor.selector, token), abi.encode(address(rewardReceiver))
            );

            // mock the vault to deposit the rewards
            vm.mockCall(
                address(rewardVault),
                abi.encodeWithSelector(RewardVault.depositRewards.selector, token, balance),
                abi.encode(2)
            );
        }

        // mock the vault to return the reward tokens
        vm.mockCall(rewardVault, abi.encodeWithSelector(RewardVault.getRewardTokens.selector), abi.encode(tokens));

        // expect the reward receiver contract to revert because one balance is higher than uint128 max
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector, 128, uint256(type(uint128).max) + 1
            )
        );
        rewardReceiver.distributeRewards();
    }

    function test_DistributesTheRewardsToTheVault() external {
        // it distributes the rewards to the vault

        address[] memory rewardsTokenList = new address[](rewardTokens.length);

        for (uint256 i; i < rewardTokens.length; i++) {
            rewardsTokenList[i] = rewardTokens[i];
            address token = rewardsTokenList[i];

            uint256 balance = uint128(vm.randomUint());

            // "airdrop" the reward token to the reward receiver
            deal(token, address(rewardReceiver), balance);

            // expect the vault to deposit the exact amount of rewards for the token
            vm.expectCall(
                address(rewardVault), abi.encodeWithSelector(RewardVault.depositRewards.selector, token, balance), 1
            );
        }

        // mock the vault to return the reward tokens then distribute the rewards
        vm.mockCall(
            rewardVault, abi.encodeWithSelector(RewardVault.getRewardTokens.selector), abi.encode(rewardsTokenList)
        );

        // mock the vault to have the reward receiver as the rewards distributor for each reward token
        for (uint256 i; i < rewardsTokenList.length; i++) {
            vm.mockCall(
                address(rewardVault), abi.encodeWithSelector(RewardVault.getRewardsDistributor.selector, rewardsTokenList[i]), abi.encode(address(rewardReceiver))
            );
        }

        rewardReceiver.distributeRewards();
    }
}

contract FakeRewardVault {
    function isRewardToken(address) external returns (bool) {}
    function depositRewards(address, uint128) external {}
}
