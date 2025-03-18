pragma solidity 0.8.28;

import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__getProtocolFeePercent is AccountantBaseTest {
    AccountantHarness accountantHarness;

    function setUp() public override {
        super.setUp();
        accountantHarness =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
    }

    function test_ReturnsTheDefaultProtocolFee() external view {
        // it returns the default protocol fee
        assertEq(accountantHarness.getProtocolFeePercent(), accountantHarness.exposed_defaultProtocolFee());
    }

    function test_ReturnsTheCurrentProtocolFee() external {
        // it returns the current protocol fee

        uint128 newProtocolFee = 0.1e18;

        vm.prank(accountantHarness.owner());
        accountantHarness.setProtocolFeePercent(newProtocolFee);

        assertEq(accountantHarness.getProtocolFeePercent(), newProtocolFee);
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountantHarness.getProtocolFeePercent();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(accountantHarness));

        // ensure the value is read from the storage
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
    }
}
