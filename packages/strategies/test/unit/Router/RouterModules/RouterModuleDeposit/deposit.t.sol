// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RouterModuleDeposit} from "src/router/RouterModuleDeposit.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";

contract RouterModuleDeposit__deposit is RouterModulesTest {
    RouterModuleDeposit internal module;

    function setUp() public override {
        super.setUp();

        module = new RouterModuleDeposit();
        _cheat_setModule(uint8(0), address(module));
    }

    function test_RevertsIfNotDelegatecallByAuthorizedContract(bytes32 randomNonce) external {
        // it reverts if not delegatecall by authorized contract

        IncorrectFakeRouter incorrectFakeRouter = new IncorrectFakeRouter{salt: randomNonce}();
        vm.assume(address(incorrectFakeRouter) != address(router));

        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));
        incorrectFakeRouter.execute(address(module));
    }

    function test_DepositsAssetsIntoTheRewardVault(address account)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it deposits assets into the reward vault

        // validate the fuzzed account address
        vm.assume(account != address(0));
        _assumeUnlabeledAddress(account);
        vm.label({account: account, newLabel: "account"});

        // deploy the asset mock
        asset = address(new ERC20Mock("Asset", "ASSET", 18));
        vm.label({account: asset, newLabel: "asset"});

        // deploy the strategy's asset mock
        strategyAsset = address(new ERC20Mock("Strategy Asset", "STRAT", 18));
        vm.label({account: strategyAsset, newLabel: "strategyAsset"});

        // clone the harnessed reward vault with the new immutable variables
        cloneRewardVault = RewardVaultHarness(
            Clones.cloneWithImmutableArgs(address(rewardVaultHarness), abi.encodePacked(gauge, asset))
        );
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});

        // set the owner balance and approve the balance for the reward vault
        uint256 OWNER_BALANCE = 1e12;
        deal(asset, account, OWNER_BALANCE);
        vm.prank(account);
        IERC20(asset).approve(address(cloneRewardVault), OWNER_BALANCE);

        // mock the dependencies needed for the deposit function flow
        (, IStrategy.PendingRewards memory pendingRewards) = _mock_test_dependencies(OWNER_BALANCE);

        // expect the checkpoint to be called with the account as the recipient
        vm.expectCall(
            address(accountant),
            abi.encodeWithSelector(
                bytes4(keccak256("checkpoint(address,address,address,uint128,(uint128,uint128),uint8,address)")),
                gauge,
                address(0),
                account,
                uint128(OWNER_BALANCE),
                pendingRewards,
                IStrategy.HarvestPolicy.CHECKPOINT,
                address(0)
            ),
            1
        );

        // mock `Registry.allowed()` to authorize the router to call the deposit function of the reward vault
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(
                IProtocolController.allowed.selector,
                address(cloneRewardVault),
                address(router),
                bytes4(keccak256("deposit(address,address,uint256,address)"))
            ),
            abi.encode(true)
        );

        // Construct the data to call the deposit router module
        bytes memory dataModule = bytes.concat(
            bytes1(uint8(0)),
            abi.encodeWithSelector(
                bytes4(keccak256("deposit(address,address,uint256,address)")),
                address(cloneRewardVault),
                account,
                OWNER_BALANCE,
                address(0)
            )
        );

        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule;

        // execute the calls as the router owner
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(address(router), account, OWNER_BALANCE, OWNER_BALANCE);

        vm.prank(account);
        bytes[] memory moduleReturn = router.execute(calls);

        // assert the shares returned by the module is the expected amount
        uint256 assets = abi.decode(moduleReturn[0], (uint256));
        assertEq(assets, OWNER_BALANCE);
    }
}

contract IncorrectFakeRouter {
    function execute(address module) external returns (bytes memory) {
        // construct the valid data for calling the modules
        bytes memory data =
            abi.encodeWithSelector(bytes4(keccak256("deposit(address,address,uint256)")), address(399), address(499), 9);

        return Address.functionDelegateCall(module, data);
    }
}
