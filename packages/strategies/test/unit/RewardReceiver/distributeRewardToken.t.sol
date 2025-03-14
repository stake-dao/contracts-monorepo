pragma solidity 0.8.28;

import {RewardReceiver} from "src/RewardReceiver.sol";
import {BaseTest} from "test/Base.t.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardVault} from "src/RewardVault.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract RewardReceiver__distributeRewardToken is BaseTest {
    RewardReceiver private rewardReceiver;
    address private rewardVault;

    function setUp() public override {
        // it returns the correct vault address

        super.setUp();

        // deploy a fake reward vault
        rewardVault = address(new FakeRewardVault());

        // deploy a RewardReceiver basic contrat and clone it with the immutable variables
        rewardReceiver =
            RewardReceiver(Clones.cloneWithImmutableArgs(address(new RewardReceiver()), abi.encodePacked(rewardVault)));
    }

    function test_RevertsIfTheTokenIsNotPresentInTheVault() external {
        // it reverts if the token is not present in the vault

        // mock the vault to be an invalid reward token
        vm.mockCall(
            address(rewardVault), abi.encodeWithSelector(FakeRewardVault.isRewardToken.selector), abi.encode(false)
        );

        // expect the reward receiver contract to revert because the token is not valid
        vm.expectRevert(RewardReceiver.InvalidToken.selector);
        rewardReceiver.distributeRewardToken(IERC20(address(rewardToken)));
    }

    function test_RevertsIfThereAreNoRewardsToDistribute() external {
        // it reverts if there are no rewards to distribute

        // mock the vault to be a valid reward token
        vm.mockCall(
            address(rewardVault), abi.encodeWithSelector(FakeRewardVault.isRewardToken.selector), abi.encode(true)
        );

        // mock the reward token to have no balance
        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

        // expect the reward receiver contract to revert because there are no rewards to distribute
        vm.expectRevert(RewardReceiver.NoRewards.selector);
        rewardReceiver.distributeRewardToken(IERC20(address(rewardToken)));
    }

    function test_RevertsIfTheBalanceIsHigherThanUint128Max(uint256 amount) external {
        // it reverts if the balance is higher than uint128 max

        vm.assume(amount > type(uint128).max);

        // mock the vault to be a valid reward token
        vm.mockCall(
            address(rewardVault), abi.encodeWithSelector(FakeRewardVault.isRewardToken.selector), abi.encode(true)
        );

        // mock the reward token to have the amount of rewards to distribute
        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(amount));

        // expect the reward receiver contract to revert because the balance is higher than uint128 max
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, amount));
        rewardReceiver.distributeRewardToken(IERC20(address(rewardToken)));
    }

    function test_AsksTheVaultToGetTheRewardTokens(uint128 amount) external {
        // it asks the vault to get the reward tokens

        vm.assume(amount > 0);

        // mock the vault to be a valid reward token
        vm.mockCall(
            address(rewardVault), abi.encodeWithSelector(FakeRewardVault.isRewardToken.selector), abi.encode(true)
        );

        // mock the reward token to have the amount of rewards to distribute
        vm.mockCall(address(rewardToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(amount));

        // expect the reward receiver contract to ask the vault to deposit the rewards
        vm.expectCall(
            address(rewardVault), abi.encodeCall(RewardVault.depositRewards, (address(rewardToken), amount)), 1
        );

        rewardReceiver.distributeRewardToken(IERC20(address(rewardToken)));
    }
}

contract FakeRewardVault {
    function isRewardToken(address) external returns (bool) {}
    function depositRewards(address, uint128) external {}
}
