pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

contract Accountant__getTotalFeePercent is Test {
    AccountantHarness accountant;

    function setUp() external {
        accountant = new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
    }

    function test_ReturnsTheCorrectValue() external {
        // it returns the default protocol fee

        assertEq(
            accountant.getTotalFeePercent(),
            accountant.exposed_defaultProtocolFee() + accountant.exposed_defaultHarvestFee()
        );
    }

    function test_ReadsTheStorage() external {
        // it reads the storage

        // record storage reads/writes
        vm.record();
        accountant.getTotalFeePercent();
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

    function exposed_defaultHarvestFee() external pure returns (uint256) {
        return DEFAULT_HARVEST_FEE;
    }
}
