// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";

contract AutocompoundedVault__getters is AutocompoundedVaultTest {
    function test_CorrectlySetsTheAsset() external view {
        // it correctly sets the asset

        assertEq(autocompoundedVault.asset(), YieldnestProtocol.SDYND);
    }

    function test_CorrectlySetsTheNameOfTheShares() external view {
        // it correctly sets the name of the shares

        assertEq(autocompoundedVault.name(), "Autocompounded Stake DAO YND");
    }

    function test_CorrectlySetsTheSymbolOfTheShares() external view {
        // it correctly sets the symbol of the shares

        assertEq(autocompoundedVault.symbol(), "asdYND");
    }

    function test_SetsTheProtocolControllerToTheGivenValue() external view {
        // it sets the protocol controller to the given value

        assertEq(address(autocompoundedVault.PROTOCOL_CONTROLLER()), address(protocolController));
    }
}
