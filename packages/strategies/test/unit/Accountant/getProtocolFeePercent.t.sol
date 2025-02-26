pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

contract Accountant__getProtocolFeePercent is Test {
    AccountantHarness accountant;

    function setUp() external {
        accountant = new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
    }

    function test_ReturnsTheDefaultProtocolFee() external {
        // it returns the default protocol fee
        assertEq(accountant.getProtocolFeePercent(), accountant.exposed_defaultProtocolFee());
    }

    function test_ReturnsTheCurrentProtocolFee() external {
        // it returns the current protocol fee

        uint256 newProtocolFee = 0.1e18;

        vm.prank(accountant.owner());
        accountant.setProtocolFeePercent(newProtocolFee);

        assertEq(accountant.getProtocolFeePercent(), newProtocolFee);
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountant.getProtocolFeePercent();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(accountant));

        // ensure the value is read from the storage
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
    }
}

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant {
    constructor(address owner, address registry, address rewardToken) Accountant(owner, registry, rewardToken) {}

    function exposed_defaultProtocolFee() external pure returns (uint256) {
        return DEFAULT_PROTOCOL_FEE;
    }
}
