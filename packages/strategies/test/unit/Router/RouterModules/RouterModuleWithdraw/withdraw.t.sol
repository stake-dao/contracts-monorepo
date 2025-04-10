// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address, Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RouterModuleWithdraw} from "src/RouterModules/RouterModuleWithdraw.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";
import {RouterModulesTest} from "test/unit/Router/RouterModules/RouterModulesTest.t.sol";

contract RouterModuleWithdraw__withdraw is RouterModulesTest {
    RouterModuleWithdraw internal module;
    address internal gauge = makeAddr("gauge");
    address internal asset;
    address internal strategyAsset;
    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    function setUp() public override {
        super.setUp();

        module = new RouterModuleWithdraw();
        _cheat_setModule(uint8(1), address(module));
    }

    function test_RevertsIfUsedDirectly(bytes32 randomNonce) external {
        // it reverts if used directly

        IncorrectFakeRouter incorrectFakeRouter = new IncorrectFakeRouter{salt: randomNonce}();
        vm.assume(address(incorrectFakeRouter) != address(router));

        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));
        incorrectFakeRouter.execute(address(module));
    }

    function test_WithdrawsAssetsFromTheRewardVaultToTheAccount(address account)
        external
        _cheat_replaceRewardVaultWithRewardVaultHarness
    {
        // it withdraws assets from the reward vault to the account

        // validate the fuzzed account address
        _assumeUnlabeledAddress(account);
        vm.assume(account != address(0));
        vm.label({account: account, newLabel: "owner"});

        // deploy asset mock
        asset = address(new ERC20Mock("Asset", "ASSET", 18));
        vm.label({account: asset, newLabel: "asset"});

        // deploying a fake ERC20 token that serves as strategy's asset
        strategyAsset = address(new ERC20Mock("Strategy Asset", "STRAT", 18));
        vm.label({account: strategyAsset, newLabel: "strategyAsset"});

        // The gauge() function reads from offset 20, so we need to ensure gauge is at that position
        // The asset() function reads from offset 40, so we need to ensure asset is at that position
        // We use abi.encodePacked to ensure proper byte alignment
        bytes memory encodedData = abi.encodePacked(gauge, asset);

        // clone the harnessed reward vault with the immutable variables
        cloneRewardVault = RewardVaultHarness(Clones.cloneWithImmutableArgs(address(rewardVaultHarness), encodedData));
        vm.label({account: address(cloneRewardVault), newLabel: "cloneRewardVault"});

        uint256 OWNER_BALANCE = 1e18;
        uint256 OWNER_ALLOWED_BALANCE = OWNER_BALANCE / 2;

        // set the owner balance and approve half the balance for the router
        deal(asset, account, OWNER_BALANCE);
        vm.prank(account);
        cloneRewardVault.approve(address(router), OWNER_ALLOWED_BALANCE);

        // mock the dependencies of the withdraw function
        _mock_test_dependencies();

        // we airdrop enough assets to the reward vault to cover the withdrawal
        deal(address(asset), address(cloneRewardVault), OWNER_BALANCE);

        // Construct the data to call the deposit router module
        bytes memory dataModule = bytes.concat(
            bytes1(uint8(1)),
            abi.encodeWithSelector(
                bytes4(keccak256("withdraw(address,uint256,address,address)")),
                address(cloneRewardVault),
                OWNER_ALLOWED_BALANCE - 1,
                address(0),
                account
            )
        );
        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule;

        // expect the withdraw event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(address(router), account, account, OWNER_ALLOWED_BALANCE - 1, OWNER_ALLOWED_BALANCE - 1);

        // make the caller withdraw the rewards. It should succeed because the allowance is enough
        vm.prank(routerOwner);
        bytes[] memory moduleReturn = router.execute(calls);

        // assert the shares returned by the module is the expected amount
        uint256 shares = abi.decode(moduleReturn[0], (uint256));
        assertEq(shares, OWNER_ALLOWED_BALANCE - 1);

        // allowance must be 1, because
        // - the owner allowed the called to spend 1 + OWNER_BALANCE / 2
        // - the caller withdrew OWNER_BALANCE / 2
        assertEq(cloneRewardVault.allowance(account, address(router)), 1);
    }

    function _mock_test_dependencies()
        internal
        returns (IAllocator.Allocation memory allocation, IStrategy.PendingRewards memory pendingRewards)
    {
        // set the allocation and pending rewards to mock values
        allocation =
            IAllocator.Allocation({asset: asset, gauge: gauge, targets: new address[](0), amounts: new uint256[](0)});
        pendingRewards = IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0});

        // mock the allocator returned by the protocol controller
        vm.mockCall(
            address(cloneRewardVault.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(allocator))
        );

        // mock the withdrawal allocation returned by the allocator
        vm.mockCall(
            address(allocator),
            abi.encodeWithSelector(IAllocator.getWithdrawalAllocation.selector),
            abi.encode(allocation)
        );

        // mock the strategy returned by the protocol controller
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.strategy.selector), abi.encode(strategyAsset)
        );

        // mock the withdraw function of the strategy
        vm.mockCall(
            address(strategyAsset), abi.encodeWithSelector(IStrategy.withdraw.selector), abi.encode(pendingRewards)
        );

        // mock the checkpoint function of the accountant
        vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.checkpoint.selector), abi.encode(true));
    }
}

contract IncorrectFakeRouter {
    function execute(address module) external returns (bytes memory) {
        // construct the valid data for calling the module
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("withdraw(address,uint256,address,address)")), address(399), 9, address(499), address(599)
        );

        return Address.functionDelegateCall(module, data);
    }
}
