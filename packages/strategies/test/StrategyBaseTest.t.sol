// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {MockSidecar} from "test/mocks/MockSidecar.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";
import {BaseTest} from "./Base.t.sol";

/// @title StrategyBaseTest
/// @notice Base test contract specifically for Strategy tests
abstract contract StrategyBaseTest is BaseTest {
    address internal gauge;
    address internal sidecar1;
    address internal sidecar2;

    StrategyHarness internal strategy;
    IAllocator.Allocation internal allocation;

    address internal accountant = makeAddr("accountant");

    function setUp() public virtual override {
        super.setUp();

        gauge = address(stakingToken);

        sidecar1 = address(new MockSidecar(gauge, address(rewardToken), accountant));
        sidecar2 = address(new MockSidecar(gauge, address(rewardToken), accountant));

        address[] memory targets = new address[](3);
        targets[0] = address(locker);
        targets[1] = sidecar1;
        targets[2] = sidecar2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        allocation = IAllocator.Allocation({asset: gauge, gauge: gauge, targets: targets, amounts: amounts});

        /// Mock the asset function of the IProtocolController interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.asset.selector, gauge),
            abi.encode(address(stakingToken))
        );

        // Mock the vault function of the IProtocolController interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.vaults.selector, gauge),
            abi.encode(address(vault))
        );

        /// Mock the `accountant` function of the `IProtocolController` interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountant)
        );

        /// Mock the `allocator` function of the `IProtocolController` interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(allocator))
        );

        /// Mock the `REWARD_TOKEN` function of the `IAccountant` interface
        vm.mockCall(
            address(accountant),
            abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector),
            abi.encode(address(rewardToken))
        );

        // Deploy the strategy
        strategy = new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        /// Cheat Allocation Targets.
        strategy._cheat_setAllocationTargets(gauge, address(allocator), allocation.targets);

        // Label the contract
        vm.label({account: address(strategy), newLabel: "Strategy"});
    }

    /// @notice Replace Strategy with StrategyHarness for testing
    modifier _cheat_replaceStrategyWithStrategyHarness() {
        _deployHarnessCode(
            "out/StrategyHarness.t.sol/StrategyHarness.json",
            abi.encode(address(registry), protocolId, address(locker), address(gateway)),
            address(strategy)
        );
        _;
    }
}
