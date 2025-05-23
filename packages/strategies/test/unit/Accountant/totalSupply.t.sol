// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__totalSupply is AccountantBaseTest {
    function test_ReturnsTheCorrectVaultSupplyAmount(uint128 supply)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it returns the correct vault supply amount
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // We are putting the contract into a state where the vault has a non-null supply
        // This function is a testing-only function that shortcut the real end-user flow
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: 0,
                supply: supply,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        assertEq(accountantHarness.totalSupply(vault), supply);
    }
}
