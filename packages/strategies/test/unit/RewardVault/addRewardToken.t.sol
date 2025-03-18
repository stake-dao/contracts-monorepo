pragma solidity 0.8.28;

import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract RewardVault__addRewardToken is RewardVaultBaseTest {
    function test_RevertIfCallerIsNotAllowed() external {
        // it revert if caller is not allowed

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector),
            abi.encode(false)
        );

        vm.expectRevert(RewardVault.OnlyRegistrar.selector);
        rewardVault.addRewardToken(makeAddr("rewardToken"), makeAddr("distributor"));
    }

    function test_RevertIfDistributorIs0() external {
        // it revert if distributor is 0

        vm.expectRevert(RewardVault.ZeroAddress.selector);
        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(makeAddr("rewardToken"), address(0));
    }

    function test_RevertIfProtocolControllerReverts() external {
        // it revert if protocol controller reverts

        vm.mockCallRevert(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector),
            "UNEXPECTED_ERROR"
        );

        vm.expectRevert("UNEXPECTED_ERROR");
        rewardVault.addRewardToken(makeAddr("rewardToken"), makeAddr("distributor"));
    }

    function test_RevertIfRewardTokenAlreadyExists(address rewardToken)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it revert if reward token already exists

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // put the contract in the state where the reward token is already added
        address[] memory addressToken = new address[](1);
        addressToken[0] = rewardToken;
        rewardVaultHarness._cheat_override_reward_tokens(addressToken);

        vm.expectRevert(RewardVault.RewardAlreadyExists.selector);
        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(rewardToken, makeAddr("distributor"));
    }

    function test_RevertIfMaxRewardTokenCountIsExceeded() external _cheat_replaceRewardVaultWithRewardVaultHarness {
        // it revert if max reward token count is exceeded

        RewardVaultHarness rewardVaultHarness = RewardVaultHarness(address(rewardVault));

        // we need to put the contract in the state where the max reward token count is exceeded
        uint256 maxRewardTokenCount = rewardVaultHarness._expose_MAX_REWARD_TOKEN_COUNT();
        address[] memory addressTokens = new address[](maxRewardTokenCount);
        for (uint256 i; i < maxRewardTokenCount; i++) {
            addressTokens[0] = address(address(bytes20(keccak256(abi.encode(i)))));
        }
        rewardVaultHarness._cheat_override_reward_tokens(addressTokens);

        // it must reverts as the max reward token count is exceeded
        vm.expectRevert(RewardVault.MaxRewardTokensExceeded.selector);
        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(makeAddr("rewardToken"), makeAddr("distributor"));
    }

    function test_AddsTheRewardTokenToTheListOfRewardTokens(address rewardToken) external {
        // it adds the reward token to the list of reward tokens

        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(rewardToken, makeAddr("distributor"));

        // we make sure the reward token is added to the list of reward tokens
        assertEq(rewardVault.getRewardTokens()[0], rewardToken);
    }

    function test_AddTheRewardTokenToTheRewardMapping(address rewardToken) external {
        // it add the reward token to the reward mapping

        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(rewardToken, makeAddr("distributor"));

        // we make sure the reward token is added to the reward mapping
        assertEq(rewardVault.isRewardToken(rewardToken), true);
    }

    function test_InitializeTheRewardDataWithTheGivenDistibutorAndDefaultDuration(
        address rewardToken,
        address distributor
    ) external {
        // it initialize the reward data with the given distibutor and default duration

        vm.assume(rewardToken != address(0));
        vm.assume(distributor != address(0));

        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(rewardToken, distributor);

        // we make sure the reward data is initialized with the given distributor and default duration
        (address rewardsDistributor, uint32 rewardsDuration,,,,) = rewardVault.rewardData(rewardToken);
        assertEq(rewardsDistributor, distributor);
        assertEq(rewardsDuration, rewardVault.DEFAULT_REWARDS_DURATION());
    }

    function test_EmitsTheRewardTokenAddedEvent(address rewardToken, address distributor) external {
        // it emits the reward token added event

        vm.assume(rewardToken != address(0));
        vm.assume(distributor != address(0));

        vm.expectEmit(true, true, true, true);
        emit RewardVault.RewardTokenAdded(rewardToken, distributor);

        _mock_allowed_authorize_caller();
        rewardVault.addRewardToken(rewardToken, distributor);
    }

    function _mock_allowed_authorize_caller() internal {
        vm.mockCall(
            address(protocolController), abi.encodeWithSelector(IProtocolController.allowed.selector), abi.encode(true)
        );
    }
}
