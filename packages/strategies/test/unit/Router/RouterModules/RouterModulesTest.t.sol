// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {Router} from "src/Router.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";
import {RewardVaultHarness} from "test/RewardVaultBaseTest.sol";

enum Allocation {
    MIXED,
    STAKEDAO,
    CONVEX
}

contract RouterModulesTest is RewardVaultBaseTest {
    Router internal router;
    address internal routerOwner;

    address internal gauge = makeAddr("gauge");
    address internal asset;

    address internal strategyAsset;

    // This implementation is the harnessed version of the reward vault cloned with the variables above
    RewardVaultHarness internal cloneRewardVault;

    function setUp() public virtual override {
        super.setUp();

        routerOwner = makeAddr("router0wner");
        vm.prank(routerOwner);
        router = new Router();
    }

    function _cheat_setModule(uint8 identifier, address module) internal {
        vm.prank(routerOwner);
        router.setModule(identifier, module);
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
