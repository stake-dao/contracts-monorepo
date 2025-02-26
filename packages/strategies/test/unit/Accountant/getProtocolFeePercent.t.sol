pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.sol";

contract Accountant__getProtocolFeePercent is BaseTest {
    AccountantHarness accountantHarness;

    function setUp() public override {
        super.setUp();
        accountantHarness = new AccountantHarness();
    }

    function test_ReturnsTheDefaultProtocolFee() external {
        // it returns the default protocol fee
        assertEq(accountantHarness.getProtocolFeePercent(), accountantHarness.exposed_defaultProtocolFee());
    }

    function test_ReturnsTheCurrentProtocolFee() external {
        // it returns the current protocol fee

        uint256 newProtocolFee = 0.1e18;

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
