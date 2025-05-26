// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/integrations/yieldnest/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";

contract AutocompoundedVault__getters is AutocompoundedVaultTest {
    AutocompoundedVault internal autocompoundedVault;

    function setUp() public override {
        super.setUp();

        autocompoundedVault = new AutocompoundedVault(address(protocolController));
    }

    function test_CorrectlySetsTheAsset() external {
        // it correctly sets the asset

        assertEq(autocompoundedVault.asset(), YieldnestProtocol.SDYND);
    }

    function test_CorrectlySetsTheNameOfTheShares() external {
        // it correctly sets the name of the shares

        assertEq(autocompoundedVault.name(), "Autocompounded Stake DAO YND");
    }

    function test_CorrectlySetsTheSymbolOfTheShares() external {
        // it correctly sets the symbol of the shares

        assertEq(autocompoundedVault.symbol(), "asdYND");
    }

    function test_SetsTheProtocolControllerToTheGivenValue() external {
        // it sets the protocol controller to the given value

        assertEq(address(autocompoundedVault.protocolController()), address(protocolController));
    }
}
