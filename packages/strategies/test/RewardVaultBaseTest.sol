// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "src/RewardVault.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
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

        /// Prepare the initialization data for the vault
        ERC20Mock asset = new ERC20Mock("Curve DAO Token", "CRV", 18);
        bytes memory data = abi.encodePacked(makeAddr("gauge"), asset);

        /// Deploy then clone the vault implementation with the initialization data
        rewardVault = RewardVault(
            Clones.cloneDeterministicWithImmutableArgs(
                address(new RewardVault(protocolId, address(registry), accountant, IStrategy.HarvestPolicy.CHECKPOINT)),
                data,
                keccak256("salt")
            )
        );

        protocolController = address(registry);
    }

    function _replaceRewardVaultWithRewardVaultHarness(address customRewardVaultAddress) internal {
        _deployHarnessCode(
            "out/RewardVaultHarness.t.sol/RewardVaultHarness.json",
            abi.encode(protocolId, address(registry), accountant, IStrategy.HarvestPolicy.CHECKPOINT),
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
