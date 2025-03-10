pragma solidity 0.8.28;

import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__getHarvestFeePercent is AccountantBaseTest {
    using stdStorage for StdStorage;

    function test_ReturnsTheCorrectValue(uint128 newHarvestFeePercent)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it returns the default protocol fee

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // test the function returns the default value in the contract
        assertEq(accountantHarness.getHarvestFeePercent(), accountantHarness.getCurrentHarvestFee());

        // illegally modify the value stored in the contract then test the getter returns it
        accountantHarness._cheat_updateFeesParamsHarvestFeePercent(newHarvestFeePercent);
        assertEq(accountantHarness.getHarvestFeePercent(), newHarvestFeePercent);
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountant.getHarvestFeePercent();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(accountant));

        // ensure the value is read from the storage
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
    }
}
