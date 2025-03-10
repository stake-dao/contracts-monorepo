// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./Base.t.sol";
import "src/Strategy.sol";
import "test/unit/Strategy/StrategyHarness.t.sol";

/// @title StrategyBaseTest
/// @notice Base test contract specifically for Strategy tests
abstract contract StrategyBaseTest is BaseTest {
    Strategy internal strategy;

    function setUp() public virtual override {
        super.setUp();

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