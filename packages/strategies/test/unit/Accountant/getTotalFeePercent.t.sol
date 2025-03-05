pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__getTotalFeePercent is BaseTest {
    AccountantHarness accountantHarness;

    function setUp() public override {
        super.setUp();
        accountantHarness =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
    }

    function test_ReturnsTheCorrectValue(uint128 newProtocolFee, uint128 newHarvestFee) external {
        // it returns the default protocol fee

        // make sure the fuzzed values are correct
        vm.assume(newProtocolFee < (accountant.MAX_FEE_PERCENT() / 2));
        vm.assume(newHarvestFee < (accountant.MAX_FEE_PERCENT() / 2));

        emit log_named_uint("newProtocolFee", newProtocolFee);
        emit log_named_uint("newHarvestFee", newHarvestFee);

        // we test that the function returns the correct value with the default parameters
        assertEq(
            accountantHarness.getTotalFeePercent(),
            accountantHarness.exposed_defaultProtocolFee() + accountantHarness.exposed_defaultHarvestFee()
        );

        // we test that the function returns the correct value fuzzed parameters
        vm.startPrank(accountantHarness.owner());
        accountantHarness.setProtocolFeePercent(newProtocolFee);
        accountantHarness.setHarvestFeePercent(newHarvestFee);
        assertEq(accountantHarness.getTotalFeePercent(), newProtocolFee + newHarvestFee);
        vm.stopPrank();
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountantHarness.getTotalFeePercent();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(accountantHarness));

        // ensure the value is read from the storage
        assertEq(reads.length, 2);
        assertEq(writes.length, 0);
    }
}
