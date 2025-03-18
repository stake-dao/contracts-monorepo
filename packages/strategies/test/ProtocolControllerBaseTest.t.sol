// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseTest} from "./Base.t.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerHarness} from "test/unit/ProtocolController/ProtocolControllerHarness.t.sol";

/// @title ProtocolControllerBaseTest
/// @notice Base test contract specifically for ProtocolController tests
abstract contract ProtocolControllerBaseTest is BaseTest {
    ProtocolController internal protocolController;

    function setUp() public virtual override {
        super.setUp();

        // Initialize ProtocolController
        protocolController = new ProtocolController();
    }

    function _deployProtocolControllerHarness() internal returns (ProtocolControllerHarness) {
        _deployHarnessCode(
            "out/ProtocolControllerHarness.t.sol/ProtocolControllerHarness.json", address(protocolController)
        );

        return ProtocolControllerHarness(address(protocolController));
    }
}
