// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__Constructor is Test {
    function test_InitializesOwner() external {
        // it initializes the owner
        // it emits the OwnershipTransferred event

        address expectedOwner = makeAddr("initialOwner");

        // we tell forge to expect the OwnershipTransferred event
        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), expectedOwner);

        // we deploy the registry and assert the owner is the deployer
        UniversalBoostRegistry registry = new UniversalBoostRegistry(expectedOwner);
        assertEq(registry.owner(), expectedOwner);
    }

    function test_InitializesConstants() external {
        // it initializes the constants correctly

        UniversalBoostRegistry registry = new UniversalBoostRegistry(makeAddr("initialOwner"));

        // Check MAX_FEE_PERCENT is set correctly (40%)
        assertEq(registry.MAX_FEE_PERCENT(), 0.4e18);

        // Check delayPeriod is set correctly (1 day)
        assertEq(registry.delayPeriod(), 1 days);
    }

    function test_InitializesWithEmptyMappings() external {
        // it initializes with empty mappings

        UniversalBoostRegistry registry = new UniversalBoostRegistry(makeAddr("initialOwner"));
        bytes4 testProtocolId = bytes4(hex"12345678");
        address testAccount = makeAddr("testAccount");

        // Check protocolConfig mapping is empty
        (
            uint128 protocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address feeReceiver
        ) = registry.protocolConfig(testProtocolId);

        assertEq(protocolFees, 0);
        assertEq(queuedProtocolFees, 0);
        assertEq(lastUpdated, 0);
        assertEq(queuedTimestamp, 0);
        assertEq(feeReceiver, address(0));

        // Check isRentingBoost mapping is empty
        assertFalse(registry.isRentingBoost(testAccount, testProtocolId));
    }

    function test_InitializesViewFunctions() external {
        // it initializes view functions correctly

        UniversalBoostRegistry registry = new UniversalBoostRegistry(makeAddr("initialOwner"));
        bytes4 testProtocolId = bytes4(hex"12345678");

        // Check hasQueuedConfig returns false for new protocol
        assertFalse(registry.hasQueuedConfig(testProtocolId));

        // Check getCommitTimestamp returns 0 for new protocol
        assertEq(registry.getCommitTimestamp(testProtocolId), 0);

        // Check delay period view functions return default values
        assertFalse(registry.hasQueuedDelayPeriod());
        assertEq(registry.getDelayPeriodCommitTimestamp(), 0);
    }

    function test_InitializesDelayPeriodFields() external {
        // it initializes delay period fields correctly

        UniversalBoostRegistry registry = new UniversalBoostRegistry(makeAddr("initialOwner"));

        // Check queued delay period fields are initialized to zero
        assertEq(registry.queuedDelayPeriod(), 0);
        assertEq(registry.delayPeriodQueuedTimestamp(), 0);
        assertFalse(registry.hasQueuedDelayPeriod());
        assertEq(registry.getDelayPeriodCommitTimestamp(), 0);
    }
}
