// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__RentBoost is Test {
    UniversalBoostRegistry internal registry;

    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");
    address internal user = makeAddr("user");

    function setUp() public {
        registry = new UniversalBoostRegistry();
    }

    function test_RentBoost() external {
        // it updates the rental status to true
        // it emits BoostRented event

        vm.startPrank(user);

        // Assert initial state is false
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        // Expect the BoostRented event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostRented(user, PROTOCOL_ID);

        // Call rentBoost
        registry.rentBoost(PROTOCOL_ID);

        // Assert rental status is now true
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_RentBoost_WhenAlreadyRenting() external {
        // it updates the rental status to true (idempotent)
        // it emits BoostRented event

        vm.startPrank(user);

        // First rent
        registry.rentBoost(PROTOCOL_ID);
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        // Expect the BoostRented event again
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostRented(user, PROTOCOL_ID);

        // Rent again (should be idempotent)
        registry.rentBoost(PROTOCOL_ID);

        // Assert rental status is still true
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_RentBoost_MultipleProtocols() external {
        // it allows renting boosts for multiple protocols simultaneously

        bytes4 protocolId1 = bytes4(hex"11111111");
        bytes4 protocolId2 = bytes4(hex"22222222");
        bytes4 protocolId3 = bytes4(hex"33333333");

        vm.startPrank(user);

        // Rent boosts for multiple protocols
        registry.rentBoost(protocolId1);
        registry.rentBoost(protocolId2);
        registry.rentBoost(protocolId3);

        // Assert all are rented
        assertTrue(registry.isRentingBoost(user, protocolId1));
        assertTrue(registry.isRentingBoost(user, protocolId2));
        assertTrue(registry.isRentingBoost(user, protocolId3));

        vm.stopPrank();
    }

    function test_RentBoost_MultipleUsers() external {
        // it allows multiple users to rent boosts for the same protocol

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // User 1 rents boost
        vm.prank(user1);
        registry.rentBoost(PROTOCOL_ID);

        // User 2 rents boost
        vm.prank(user2);
        registry.rentBoost(PROTOCOL_ID);

        // User 3 rents boost
        vm.prank(user3);
        registry.rentBoost(PROTOCOL_ID);

        // Assert all users are renting
        assertTrue(registry.isRentingBoost(user1, PROTOCOL_ID));
        assertTrue(registry.isRentingBoost(user2, PROTOCOL_ID));
        assertTrue(registry.isRentingBoost(user3, PROTOCOL_ID));
    }

    function test_RentBoost_FuzzedProtocolId(bytes4 protocolId) external {
        // it works with any protocol ID

        vm.startPrank(user);

        // Assert initial state is false
        assertFalse(registry.isRentingBoost(user, protocolId));

        // Expect the BoostRented event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostRented(user, protocolId);

        // Call rentBoost
        registry.rentBoost(protocolId);

        // Assert rental status is now true
        assertTrue(registry.isRentingBoost(user, protocolId));

        vm.stopPrank();
    }

    function test_RentBoost_FuzzedUser(address fuzzedUser) external {
        // it works with any user address

        vm.assume(fuzzedUser != address(0));

        vm.startPrank(fuzzedUser);

        // Assert initial state is false
        assertFalse(registry.isRentingBoost(fuzzedUser, PROTOCOL_ID));

        // Expect the BoostRented event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostRented(fuzzedUser, PROTOCOL_ID);

        // Call rentBoost
        registry.rentBoost(PROTOCOL_ID);

        // Assert rental status is now true
        assertTrue(registry.isRentingBoost(fuzzedUser, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_RentBoost_DoesNotAffectOtherMappings() external {
        // it does not affect protocol configurations or other users' rentals

        address otherUser = makeAddr("otherUser");
        bytes4 otherProtocolId = bytes4(hex"87654321");

        vm.startPrank(user);

        // Rent boost
        registry.rentBoost(PROTOCOL_ID);

        // Check that other users and protocols are unaffected
        assertFalse(registry.isRentingBoost(otherUser, PROTOCOL_ID));
        assertFalse(registry.isRentingBoost(user, otherProtocolId));
        assertFalse(registry.isRentingBoost(otherUser, otherProtocolId));

        // Check that protocol config remains empty
        (
            uint128 protocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address feeReceiver,
            address queuedFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        assertEq(protocolFees, 0);
        assertEq(queuedProtocolFees, 0);
        assertEq(lastUpdated, 0);
        assertEq(queuedTimestamp, 0);
        assertEq(feeReceiver, address(0));
        assertEq(queuedFeeReceiver, address(0));

        vm.stopPrank();
    }
}
