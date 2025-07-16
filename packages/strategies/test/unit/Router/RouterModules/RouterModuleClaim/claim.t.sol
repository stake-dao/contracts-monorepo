// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {StdCheats} from "forge-std/src/StdCheats.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RouterModuleClaim} from "src/router/RouterModuleClaim.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";

contract RouterModuleClaim__claim is RouterModulesTest {
    RouterModuleClaim internal module;
    address[] internal tokens;

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

        // register the claim module
        module = new RouterModuleClaim();
        _cheat_setModule(uint8(2), address(module));
    }

    function test_RevertsIfUsedDirectly() external {
        // it reverts if used directly

        vm.expectRevert(abi.encodeWithSelector(RewardVault.OnlyAllowed.selector));
        module.claim(address(rewardVault), tokens, makeAddr("receiver"));
    }

    function test_RevertsIfNotDelegatecallByAuthorizedContract(bytes32 randomNonce) external {
        // it reverts if not delegatecall by authorized contract

        IncorrectFakeRouter incorrectFakeRouter = new IncorrectFakeRouter{salt: randomNonce}();
        vm.assume(address(incorrectFakeRouter) != address(router));

        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));
        incorrectFakeRouter.execute(address(module));
    }

    function test_ClaimsRewardsFromTheRewardVault(address account, address receiver)
        external
        setup_claim(account, receiver)
    {
        // it claims rewards from the reward vault

        uint256 balanceBefore = IERC20(address(rewardToken)).balanceOf(receiver);

        // Construct the data to call the deposit router module
        bytes memory dataModule = bytes.concat(
            bytes1(RouterIdentifierMapping.CLAIM),
            abi.encodeWithSelector(
                bytes4(keccak256("claim(address,address[],address)")), address(cloneRewardVault), tokens, receiver
            )
        );
        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule;

        // execute the calls as the router owner
        vm.prank(account);
        bytes[] memory moduleReturn = router.execute(calls);

        // assert the rewards are transferred to the receiver
        uint256[] memory amounts = abi.decode(moduleReturn[0], (uint256[]));
        assertEq(IERC20(address(rewardToken)).balanceOf(receiver), balanceBefore + amounts[0]);
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

        _;
    }
}

contract IncorrectFakeRouter {
    function execute(address module) external returns (bytes memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(678);

        // construct the valid data for calling the modules
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("claim(address,address,address[],address)")),
            address(399),
            address(499),
            tokens,
            address(599)
        );

        return Address.functionDelegateCall(module, data);
    }
}
