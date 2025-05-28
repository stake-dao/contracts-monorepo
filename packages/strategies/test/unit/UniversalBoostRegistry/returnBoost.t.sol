// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__ReturnBoost is Test {
    UniversalBoostRegistry internal registry;

    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");
    address internal user = makeAddr("user");

    function setUp() public {
        registry = new UniversalBoostRegistry(makeAddr("initialOwner"));
    }

    function test_ReturnBoost_WhenCurrentlyRenting() external {
        // it updates the rental status to false
        // it emits BoostReturned event

        vm.startPrank(user);

        // First rent the boost
        registry.rentBoost(PROTOCOL_ID);
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        // Expect the BoostReturned event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(user, PROTOCOL_ID);

        // Return the boost
        registry.returnBoost(PROTOCOL_ID);

        // Assert rental status is now false
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_ReturnBoost_WhenNotRenting() external {
        // it updates the rental status to false (idempotent)
        // it emits BoostReturned event

        vm.startPrank(user);

        // Assert initial state is false
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        // Expect the BoostReturned event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(user, PROTOCOL_ID);

        // Return boost (should be idempotent)
        registry.returnBoost(PROTOCOL_ID);

        // Assert rental status is still false
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_ReturnBoost_MultipleReturns() external {
        // it allows multiple returns (idempotent)

        vm.startPrank(user);

        // Rent and return boost
        registry.rentBoost(PROTOCOL_ID);
        registry.returnBoost(PROTOCOL_ID);
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        // Return again
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(user, PROTOCOL_ID);

        registry.returnBoost(PROTOCOL_ID);
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        // Return once more
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(user, PROTOCOL_ID);

        registry.returnBoost(PROTOCOL_ID);
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_ReturnBoost_MultipleProtocols() external {
        // it allows returning boosts for specific protocols independently

        bytes4 protocolId1 = bytes4(hex"11111111");
        bytes4 protocolId2 = bytes4(hex"22222222");
        bytes4 protocolId3 = bytes4(hex"33333333");

        vm.startPrank(user);

        // Rent boosts for multiple protocols
        registry.rentBoost(protocolId1);
        registry.rentBoost(protocolId2);
        registry.rentBoost(protocolId3);

        // Return boost for protocolId2 only
        registry.returnBoost(protocolId2);

        // Assert protocolId2 is returned but others are still rented
        assertTrue(registry.isRentingBoost(user, protocolId1));
        assertFalse(registry.isRentingBoost(user, protocolId2));
        assertTrue(registry.isRentingBoost(user, protocolId3));

        vm.stopPrank();
    }

    function test_ReturnBoost_MultipleUsers() external {
        // it allows users to return boosts independently

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // All users rent boost
        vm.prank(user1);
        registry.rentBoost(PROTOCOL_ID);

        vm.prank(user2);
        registry.rentBoost(PROTOCOL_ID);

        vm.prank(user3);
        registry.rentBoost(PROTOCOL_ID);

        // User2 returns boost
        vm.prank(user2);
        registry.returnBoost(PROTOCOL_ID);

        // Assert user2 returned but others still renting
        assertTrue(registry.isRentingBoost(user1, PROTOCOL_ID));
        assertFalse(registry.isRentingBoost(user2, PROTOCOL_ID));
        assertTrue(registry.isRentingBoost(user3, PROTOCOL_ID));
    }

    function test_ReturnBoost_RentReturnCycle() external {
        // it allows rent-return cycles

        vm.startPrank(user);

        for (uint256 i = 0; i < 5; i++) {
            // Rent boost
            registry.rentBoost(PROTOCOL_ID);
            assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

            // Return boost
            registry.returnBoost(PROTOCOL_ID);
            assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));
        }

        vm.stopPrank();
    }

    function test_ReturnBoost_FuzzedProtocolId(bytes4 protocolId) external {
        // it works with any protocol ID

        vm.startPrank(user);

        // Rent first
        registry.rentBoost(protocolId);
        assertTrue(registry.isRentingBoost(user, protocolId));

        // Expect the BoostReturned event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(user, protocolId);

        // Return boost
        registry.returnBoost(protocolId);

        // Assert rental status is now false
        assertFalse(registry.isRentingBoost(user, protocolId));

        vm.stopPrank();
    }

    function test_ReturnBoost_FuzzedUser(address fuzzedUser) external {
        // it works with any user address

        vm.assume(fuzzedUser != address(0));

        vm.startPrank(fuzzedUser);

        // Rent first
        registry.rentBoost(PROTOCOL_ID);
        assertTrue(registry.isRentingBoost(fuzzedUser, PROTOCOL_ID));

        // Expect the BoostReturned event
        vm.expectEmit(true, true, false, false);
        emit UniversalBoostRegistry.BoostReturned(fuzzedUser, PROTOCOL_ID);

        // Return boost
        registry.returnBoost(PROTOCOL_ID);

        // Assert rental status is now false
        assertFalse(registry.isRentingBoost(fuzzedUser, PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_ReturnBoost_DoesNotAffectOtherMappings() external {
        // it does not affect protocol configurations or other users' rentals

        address otherUser = makeAddr("otherUser");
        bytes4 otherProtocolId = bytes4(hex"87654321");

        vm.startPrank(user);

        // Rent boost for user and other user
        registry.rentBoost(PROTOCOL_ID);
        vm.stopPrank();

        vm.prank(otherUser);
        registry.rentBoost(PROTOCOL_ID);

        vm.startPrank(user);

        // Return boost for user only
        registry.returnBoost(PROTOCOL_ID);

        // Check that other user is still renting
        assertFalse(registry.isRentingBoost(user, PROTOCOL_ID));
        assertTrue(registry.isRentingBoost(otherUser, PROTOCOL_ID));

        // Check that other protocols are unaffected
        assertFalse(registry.isRentingBoost(user, otherProtocolId));
        assertFalse(registry.isRentingBoost(otherUser, otherProtocolId));

        // Check that protocol config remains empty
        (
            uint128 protocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address feeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        assertEq(protocolFees, 0);
        assertEq(queuedProtocolFees, 0);
        assertEq(lastUpdated, 0);
        assertEq(queuedTimestamp, 0);
        assertEq(feeReceiver, address(0));

        vm.stopPrank();
    }
}
