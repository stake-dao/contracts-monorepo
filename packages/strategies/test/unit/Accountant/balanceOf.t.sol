pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__balanceOf is AccountantBaseTest {
    function test_ReturnsTheCorrectUserBalanceForSpecificVault(uint128 amount)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it returns the correct user balance for specific vault

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        address user = makeAddr("user");

        // We are putting the contract into a state where the vault has a non-null supply
        // This function is a testing-only function that shortcut the real end-user flow
        accountantHarness._cheat_updateUserData(
            vault, user, Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );

        assertEq(accountantHarness.balanceOf(vault, user), amount);
    }
}
