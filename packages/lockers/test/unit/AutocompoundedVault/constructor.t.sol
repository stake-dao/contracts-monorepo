// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {YieldnestLocker} from "@address-book/src/YieldnestEthereum.sol";

contract AutocompoundedVault__constructor is AutocompoundedVaultTest {
    function test_CorrectlySetsTheAsset() external view {
        // it correctly sets the asset

        assertEq(autocompoundedVault.asset(), YieldnestLocker.SDYND);
    }

    function test_CorrectlySetsTheNameOfTheShares() external view {
        // it correctly sets the name of the shares

        assertEq(autocompoundedVault.name(), "Autocompounded Stake DAO YND");
    }

    function test_CorrectlySetsTheSymbolOfTheShares() external view {
        // it correctly sets the symbol of the shares

        assertEq(autocompoundedVault.symbol(), "asdYND");
    }

    function test_CorrectlySetsTheOwner() external view {
        // it correctly sets the owner

        assertEq(autocompoundedVault.owner(), owner);
    }
}
