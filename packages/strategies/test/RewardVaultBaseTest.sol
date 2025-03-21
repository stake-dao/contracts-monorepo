// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "src/RewardVault.sol";
import "test/unit/RewardVault/RewardVaultHarness.t.sol";
import "./Base.t.sol";

/// @title RewardVaultTest
/// @notice Base test contract specifically for RewardVault tests
abstract contract RewardVaultBaseTest is BaseTest {
    RewardVault internal rewardVault;
    RewardVaultHarness internal rewardVaultHarness;

    address internal protocolController;
    address internal immutable accountant = makeAddr("accountant");

    function setUp() public virtual override {
        super.setUp();

        // Initialize Accountant
        rewardVault = new RewardVault(protocolId, address(registry), accountant, false);
        protocolController = address(registry);
    }

    function _replaceRewardVaultWithRewardVaultHarness(address customRewardVaultAddress) internal {
        _deployHarnessCode(
            "out/RewardVaultHarness.t.sol/RewardVaultHarness.json",
            abi.encode(protocolId, address(registry), accountant, false),
            customRewardVaultAddress
        );
        rewardVaultHarness = RewardVaultHarness(customRewardVaultAddress);
    }

    modifier _cheat_replaceRewardVaultWithRewardVaultHarness() {
        _replaceRewardVaultWithRewardVaultHarness(address(rewardVault));
        vm.label({account: address(rewardVaultHarness), newLabel: "RewardVaultHarness"});

        _;
    }
}
