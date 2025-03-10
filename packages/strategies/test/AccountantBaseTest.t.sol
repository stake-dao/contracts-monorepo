// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./Base.t.sol";
import "src/Accountant.sol";
import "test/unit/Accountant/AccountantHarness.t.sol";

import {MockStrategy} from "test/mocks/MockStrategy.sol";

/// @title AccountantBaseTest
/// @notice Base test contract specifically for Accountant tests
abstract contract AccountantBaseTest is BaseTest {
    MockStrategy internal strategy;
    Accountant internal accountant;

    function setUp() public virtual override {
        super.setUp();

        // Initialize Strategy
        strategy = new MockStrategy(address(rewardToken));

        // Initialize Accountant
        accountant = new Accountant(owner, address(registry), address(rewardToken), protocolId);

        /// Set the vault
        registry.setVault(vault);
        // Set the strategy in registry
        registry.setStrategy(address(strategy));

        // Label the contract
        vm.label({account: address(strategy), newLabel: "Strategy"});
        vm.label({account: address(accountant), newLabel: "Accountant"});
    }

    /// @notice Helper to bound a valid protocol fee
    function _boundValidProtocolFee(uint128 newProtocolFee) internal view returns (uint128) {
        return
            uint128(bound(uint256(newProtocolFee), 1, accountant.MAX_FEE_PERCENT() - accountant.getHarvestFeePercent()));
    }

    /// @notice Replace Accountant with AccountantHarness for testing
    /// @dev Only the runtime code stored for the Accountant contract is replaced with AccountantHarness's code.
    ///      The storage stays the same, every variables stored at Accountant's construction time will be usable
    ///      by the AccountantHarness implementation.
    modifier _cheat_replaceAccountantWithAccountantHarness() {
        _deployHarnessCode(
            "out/AccountantHarness.t.sol/AccountantHarness.json",
            abi.encode(owner, address(registry), address(rewardToken), protocolId),
            address(accountant)
        );
        _;
    }
}
