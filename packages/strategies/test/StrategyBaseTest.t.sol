// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./Base.t.sol";
import "test/unit/Strategy/StrategyHarness.t.sol";
import "src/interfaces/IAccountant.sol";

/// @title StrategyBaseTest
/// @notice Base test contract specifically for Strategy tests
abstract contract StrategyBaseTest is BaseTest {
    StrategyHarness internal strategy;

    address internal accountant = makeAddr("accountant");

    function setUp() public virtual override {
        super.setUp();

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
