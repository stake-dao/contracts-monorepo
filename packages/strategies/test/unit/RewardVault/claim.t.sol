// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdCheats} from "forge-std/src/StdCheats.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {RewardVault} from "src/RewardVault.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultBaseTest, RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

contract RewardVault__claim is RewardVaultBaseTest {
    address internal gauge = makeAddr("gauge");
    address internal asset;
    address internal strategyAsset;
    address[] internal tokens;

    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    function setUp() public virtual override {
        // we're deploying and setting up the reward vault as it would be in a real deployment
        super.setUp();

        // the implementation of reward vault is replaced with the harness variant for testing purposes
        _replaceRewardVaultWithRewardVaultHarness(address(rewardVault));

        // deploy asset mock
        asset = address(new ERC20Mock("Asset", "ASSET", 18));
        vm.label({account: asset, newLabel: "asset"});

        // set the reward tokens that the vault will support
        tokens.push(address(rewardToken));

        // clone the harnessed reward vault with the immutable variables
        bytes memory encodedData = abi.encodePacked(gauge, asset);
        cloneRewardVault = RewardVaultHarness(Clones.cloneWithImmutableArgs(address(rewardVaultHarness), encodedData));
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});
    }

    function test_RevertsIfCallerIsNotAuthorizedGivenAccount(address account, address caller, address receiver)
        external
    {
        // it reverts if caller is not authorized
        vm.expectRevert(abi.encodeWithSelector(RewardVault.OnlyAllowed.selector));
        vm.prank(caller);
        cloneRewardVault.claim(account, tokens, receiver);
    }

    modifier setup_claim(address account, address receiver) {
        vm.assume(account != address(0));
        vm.assume(receiver != address(0));
        vm.label({account: account, newLabel: "account"});
        vm.label({account: receiver, newLabel: "receiver"});

        // add the reward token to the vault
        cloneRewardVault._cheat_override_reward_tokens(tokens);

        // Put the account in a state with no rewards paid out and no rewards available to claim
        cloneRewardVault._cheat_override_account_data(
            account,
            tokens[0],
            RewardVault.AccountData({
                // Total rewards paid out to the account since the last update.
                rewardPerTokenPaid: 0,
                // Total rewards currently available for the account to claim,
                // based on the difference between rewardPerToken and rewardPerTokenPaid.
                claimable: 0
            })
        );

        // give reward token to the rewardvault
        uint256 rewardTokenBalance = type(uint128).max;
        StdCheats.deal(address(rewardToken), address(cloneRewardVault), rewardTokenBalance);
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(IAccountant.totalSupply.selector, address(cloneRewardVault)),
            abi.encode(rewardTokenBalance)
        );
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(IAccountant.balanceOf.selector, address(cloneRewardVault), account),
            abi.encode(1e20)
        );

        // mock the protocol controller to allow the caller to interact with the reward vault
        vm.mockCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.allowed.selector),
            abi.encode(true)
        );

        (uint128 rewardPerTokenPaid,) = cloneRewardVault.accountData(account, address(rewardToken));
        assertEq(rewardPerTokenPaid, 0);

        (, uint32 lastUpdateTime,,,) = cloneRewardVault.rewardData(address(rewardToken));
        assertEq(lastUpdateTime, block.timestamp);

        // move time forward for a few days
        vm.warp(4 days);

        // assert the receiver has no rewards before calling the claim function
        assertEq(IERC20(address(rewardToken)).balanceOf(receiver), 0);

        _;
    }

    function test_RevertsIfGivenTokensIsNotSupported(address caller, address receiver) external {
        // it reverts if given tokens is not supported

        vm.expectRevert(abi.encodeWithSelector(RewardVault.InvalidRewardToken.selector));
        vm.prank(caller);
        cloneRewardVault.claim(tokens, receiver);
    }

    function test_UpdatesAccountData(address account, address receiver) external setup_claim(account, receiver) {
        // it updates account data

        // claim the rewards and assert the rewards are transferred to the receiver
        cloneRewardVault.claim(account, tokens, receiver);

        (uint128 rewardPerTokenPaid,) = cloneRewardVault.accountData(account, address(rewardToken));
        assertGt(rewardPerTokenPaid, 0);
    }

    function test_UpdatesRewardTokenState(address account, address receiver) external setup_claim(account, receiver) {
        // it updates reward token state

        // claim the rewards and assert the rewards are transferred to the receiver
        cloneRewardVault.claim(account, tokens, receiver);

        (, uint32 lastUpdateTime,,,) = cloneRewardVault.rewardData(address(rewardToken));
        assertEq(lastUpdateTime, block.timestamp);
    }

    function test_ClaimsAccountRewardToReceiver(address account, address receiver)
        external
        setup_claim(account, receiver)
    {
        // it claims account reward to receiver

        // claim the rewards and assert the rewards are transferred to the receiver
        uint256[] memory amounts = cloneRewardVault.claim(account, tokens, receiver);
        assertEq(IERC20(address(rewardToken)).balanceOf(receiver), amounts[0]);
    }

    function test_ClaimsCallerRewardToReceiver(address account, address receiver)
        external
        setup_claim(account, receiver)
    {
        // it claims caller reward to receiver

        // ensure we do not call the protocol controller to check if the caller is allowed as the function is public
        vm.expectCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeCall(IProtocolController.allowed, (address(cloneRewardVault), account, 0x27f85910)),
            0
        );

        // claim the rewards and assert the rewards are transferred to the receiver
        vm.prank(account);
        uint256[] memory amounts = cloneRewardVault.claim(tokens, receiver);
        assertEq(IERC20(address(rewardToken)).balanceOf(receiver), amounts[0]);
    }
}
