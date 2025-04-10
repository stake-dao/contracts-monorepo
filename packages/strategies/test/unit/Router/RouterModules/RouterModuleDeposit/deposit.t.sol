// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RouterModuleDeposit} from "src/RouterModules/RouterModuleDeposit.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";

contract RouterModuleDeposit__deposit is RouterModulesTest {
    RouterModuleDeposit internal module;

    address internal gauge = makeAddr("gauge");
    address internal asset;
    address internal strategyAsset;

    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    enum Allocation {
        MIXED,
        STAKEDAO,
        CONVEX
    }

    function setUp() public override {
        super.setUp();

        module = new RouterModuleDeposit();
        _cheat_setModule(uint8(0), address(module));
    }

    function test_RevertsIfUsedDirectly() external {
        // it reverts if used directly

        // call `deposit(address,address,uint256)`
        vm.expectRevert(abi.encodeWithSelector(RewardVault.OnlyAllowed.selector));
        module.deposit(address(rewardVault), makeAddr("account"), vm.randomUint());

        // call `deposit(address,address,uint256,address)`
        vm.expectRevert(abi.encodeWithSelector(RewardVault.OnlyAllowed.selector));
        module.deposit(address(rewardVault), makeAddr("account"), vm.randomUint(), makeAddr("referrer"));
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
            abi.encodeCall(
                IAccountant.checkpoint, (gauge, address(0), account, uint128(OWNER_BALANCE), pendingRewards, false)
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
                bytes4(keccak256("deposit(address,uint256)"))
            ),
            abi.encode(true)
        );

        // Construct the data to call the deposit router module
        bytes memory dataModule = bytes.concat(
            bytes1(uint8(0)),
            abi.encodeWithSelector(
                bytes4(keccak256("deposit(address,address,uint256)")), address(cloneRewardVault), account, OWNER_BALANCE
            )
        );
        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule;

        // execute the calls as the router owner
        vm.prank(routerOwner);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(address(router), account, OWNER_BALANCE, OWNER_BALANCE);
        bytes[] memory moduleReturn = router.execute(calls);

        // assert the shares returned by the module is the expected amount
        uint256 assets = abi.decode(moduleReturn[0], (uint256));
        assertEq(assets, OWNER_BALANCE);
    }

    function _mock_test_dependencies(uint256 accountBalance)
        internal
        returns (IAllocator.Allocation memory allocation, IStrategy.PendingRewards memory pendingRewards)
    {
        uint256[] memory amounts;
        amounts = new uint256[](1);
        amounts[0] = accountBalance;

        address[] memory targets;
        targets = new address[](1);
        targets[0] = makeAddr("TARGET_INHOUSE_STRATEGY");

        // set the allocation and pending rewards to mock values
        allocation = IAllocator.Allocation({asset: asset, gauge: gauge, targets: targets, amounts: amounts});
        pendingRewards = IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0});

        // mock the allocator returned by the protocol controller
        vm.mockCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(allocator))
        );

        // mock the withdrawal allocation returned by the allocator
        vm.mockCall(
            address(allocator), abi.encodeWithSelector(IAllocator.getDepositAllocation.selector), abi.encode(allocation)
        );

        // mock the strategy returned by the protocol controller
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.strategy.selector), abi.encode(strategyAsset)
        );

        // mock the deposit function of the strategy
        vm.mockCall(
            address(strategyAsset), abi.encodeWithSelector(IStrategy.deposit.selector), abi.encode(pendingRewards)
        );

        // mock the checkpoint function of the accountant
        vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.checkpoint.selector), abi.encode(true));
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
