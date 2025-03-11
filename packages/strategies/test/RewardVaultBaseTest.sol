// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./Base.t.sol";
import "src/RewardVault.sol";
import "test/unit/RewardVault/RewardVaultHarness.t.sol";

/// @title RewardVaultTest
/// @notice Base test contract specifically for RewardVault tests
abstract contract RewardVaultBaseTest is BaseTest {
    RewardVault internal rewardVault;

    address internal protocolController;
    address internal immutable accountant = makeAddr("accountant");

    function setUp() public virtual override {
        super.setUp();

        // Initialize Accountant
        rewardVault = new RewardVault(protocolId, address(registry), accountant);
        protocolController = address(registry);
    }

    /// @notice Replace Strategy with RewardVaultHarness for testing
    modifier _cheat_replaceRewardVaultWithRewardVaultHarness() {
        _deployHarnessCode(
            "out/RewardVaultHarness.t.sol/RewardVaultHarness.json",
            abi.encode(protocolId, address(registry), accountant),
            address(rewardVault)
        );
        _;
    }
}
