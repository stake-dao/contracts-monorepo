// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerHarness} from "test/unit/ProtocolController/ProtocolControllerHarness.t.sol";
import {BaseTest, MockStrategy} from "./Base.t.sol";

/// @title ProtocolControllerBaseTest
/// @notice Base test contract specifically for ProtocolController tests
abstract contract ProtocolControllerBaseTest is BaseTest {
    ProtocolController internal protocolController;
    MockStrategy internal strategy;

    function setUp() public virtual override {
        super.setUp();

        // Initialize ProtocolController
        protocolController = new ProtocolController(address(this));

        // Initialize Strategy
        strategy = new MockStrategy(address(rewardToken));

        // Set the strategy in the protocol controller
        protocolController.setStrategy(protocolId, address(strategy));
    }

    function _deployProtocolControllerHarness() internal returns (ProtocolControllerHarness) {
        _deployHarnessCode(
            "out/ProtocolControllerHarness.t.sol/ProtocolControllerHarness.json",
            abi.encode(address(this)),
            address(protocolController)
        );

        return ProtocolControllerHarness(address(protocolController));
    }
}
