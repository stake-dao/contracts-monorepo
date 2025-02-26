pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.sol";

contract Accountant__getTotalFeePercent is BaseTest {
    AccountantHarness accountantHarness;

    function setUp() public override {
        super.setUp();
        accountantHarness = new AccountantHarness();
    }

    function test_ReturnsTheCorrectValue() external {
        // it returns the default protocol fee

        assertEq(
            accountantHarness.getTotalFeePercent(),
            accountantHarness.exposed_defaultProtocolFee() + accountantHarness.exposed_defaultHarvestFee()
        );
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountantHarness.getTotalFeePercent();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(accountantHarness));

        // ensure the value is read from the storage
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
    }
}
