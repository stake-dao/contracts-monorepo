pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__getPendingRewards is AccountantBaseTest {
    function test_ReturnsTheCorrectUserPendingRewardsForSpecificVault(uint128 pendingRewards)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it returns the correct user balance for specific vault

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        address user = makeAddr("user");

        // We are putting the contract into a state where the vault has a non-null state
        // This function is a testing-only function that shortcut the real end-user flow
        accountantHarness._cheat_updateUserData(
            vault, user, Accountant.AccountData({balance: 0, integral: 0, pendingRewards: pendingRewards})
        );

        assertEq(accountantHarness.getPendingRewards(vault, user), pendingRewards);
    }

    function test_ReturnsTheCorrectVaultPendingRewards(uint128 pendingRewards)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it returns the correct vault pending rewards

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // We are putting the contract into a state where the vault has a non-null state
        // This function is a testing-only function that shortcut the real end-user flow
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: 0,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: pendingRewards,
                netCredited: 0
            })
        );

        assertEq(accountantHarness.getPendingRewards(vault), pendingRewards);
    }
}
