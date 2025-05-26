// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/integrations/yieldnest/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";

contract AutocompoundedVault__getters is AutocompoundedVaultTest {
    AutocompoundedVault internal autocompoundedVault;

    function setUp() public override {
        super.setUp();

        autocompoundedVault = new AutocompoundedVault(address(protocolController));
    }

    function test_ReturnsTheVersionOfTheContract() external {
        // it returns the version of the contract

        assertEq(autocompoundedVault.version(), "1.0.0");
    }

    function test_ReturnsTheProtocolController() external {
        // it returns the protocol controller

        assertEq(address(autocompoundedVault.protocolController()), address(protocolController));
    }

    function test_ReturnsTheStreamingPeriod() external {
        // it returns the streaming period

        assertEq(autocompoundedVault.STREAMING_PERIOD(), uint128(7 days));
    }
}
