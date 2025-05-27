// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";

contract AutocompoundedVault__getters is AutocompoundedVaultTest {
    function test_ReturnsTheVersionOfTheContract() external view {
        // it returns the version of the contract

        assertEq(autocompoundedVault.version(), "1.0.0");
    }

    function test_ReturnsTheProtocolController() external view {
        // it returns the protocol controller

        assertEq(address(autocompoundedVault.PROTOCOL_CONTROLLER()), address(protocolController));
    }

    function test_ReturnsTheStreamingPeriod() external view {
        // it returns the streaming period

        assertEq(autocompoundedVault.STREAMING_PERIOD(), uint128(7 days));
    }

    function test_ReturnsTheCorrectNameOfTheShares() external view {
        // it returns the correct name of the shares

        assertEq(autocompoundedVault.name(), "Autocompounded Stake DAO YND");
    }

    function test_ReturnsTheCorrectSymbolOfTheShares() external view {
        // it returns the correct symbol of the shares

        assertEq(autocompoundedVault.symbol(), "asdYND");
    }
}
