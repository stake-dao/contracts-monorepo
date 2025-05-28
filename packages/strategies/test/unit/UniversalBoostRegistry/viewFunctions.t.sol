// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__ViewFunctions is Test {
    UniversalBoostRegistry internal registry;

    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");
    address internal owner;
    address internal feeReceiver = makeAddr("feeReceiver");

    function setUp() public {
        registry = new UniversalBoostRegistry(makeAddr("initialOwner"));
        owner = registry.owner();
    }

    function test_HasQueuedConfig_ReturnsFalseWhenNoConfig() external {
        // it returns false when no configuration is queued

        assertFalse(registry.hasQueuedConfig(PROTOCOL_ID));
    }

    function test_HasQueuedConfig_ReturnsTrueWhenConfigQueued() external {
        // it returns true when configuration is queued

        vm.prank(owner);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);

        assertTrue(registry.hasQueuedConfig(PROTOCOL_ID));
    }

    function test_HasQueuedConfig_ReturnsFalseAfterCommit() external {
        // it returns false after configuration is committed

        vm.startPrank(owner);

        // Queue configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);
        assertTrue(registry.hasQueuedConfig(PROTOCOL_ID));

        vm.stopPrank();

        // Advance time and commit
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Should return false after commit
        assertFalse(registry.hasQueuedConfig(PROTOCOL_ID));
    }

    function test_HasQueuedConfig_UpdatesWhenNewConfigQueued() external {
        // it updates when new configuration overwrites previous queue

        vm.startPrank(owner);

        // Queue first configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18, feeReceiver);
        assertTrue(registry.hasQueuedConfig(PROTOCOL_ID));

        // Queue second configuration (should overwrite)
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.2e18, feeReceiver);
        assertTrue(registry.hasQueuedConfig(PROTOCOL_ID));

        vm.stopPrank();
    }

    function test_GetCommitTimestamp_ReturnsZeroWhenNoConfig() external {
        // it returns zero when no configuration is queued

        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), 0);
    }

    function test_GetCommitTimestamp_ReturnsCorrectTimestampWhenQueued() external {
        // it returns correct commit timestamp when configuration is queued

        vm.startPrank(owner);

        uint64 queueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);

        uint64 expectedCommitTime = queueTime + registry.delayPeriod();
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedCommitTime);

        vm.stopPrank();
    }

    function test_GetCommitTimestamp_ReturnsZeroAfterCommit() external {
        // it returns zero after configuration is committed

        vm.startPrank(owner);

        // Queue configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);
        assertGt(registry.getCommitTimestamp(PROTOCOL_ID), 0);

        vm.stopPrank();

        // Advance time and commit
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Should return zero after commit
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), 0);
    }

    function test_GetCommitTimestamp_UpdatesWhenNewConfigQueued() external {
        // it updates when new configuration is queued

        vm.startPrank(owner);

        // Queue first configuration
        uint64 firstQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18, feeReceiver);

        uint64 firstExpectedCommit = firstQueueTime + registry.delayPeriod();
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), firstExpectedCommit);

        // Advance time and queue second configuration
        vm.warp(block.timestamp + 1 hours);
        uint64 secondQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.2e18, feeReceiver);

        uint64 secondExpectedCommit = secondQueueTime + registry.delayPeriod();
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), secondExpectedCommit);

        vm.stopPrank();
    }

    function test_ViewFunctions_MultipleProtocols() external {
        // it handles multiple protocols independently

        bytes4 protocolId1 = bytes4(hex"11111111");
        bytes4 protocolId2 = bytes4(hex"22222222");
        bytes4 protocolId3 = bytes4(hex"33333333");

        vm.startPrank(owner);

        // Queue configurations for first two protocols only
        uint64 queueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(protocolId1, 0.1e18, feeReceiver);
        registry.queueNewProtocolConfig(protocolId2, 0.2e18, feeReceiver);

        vm.stopPrank();

        // Check view functions for each protocol
        assertTrue(registry.hasQueuedConfig(protocolId1));
        assertTrue(registry.hasQueuedConfig(protocolId2));
        assertFalse(registry.hasQueuedConfig(protocolId3));

        uint64 expectedCommitTime = queueTime + registry.delayPeriod();
        assertEq(registry.getCommitTimestamp(protocolId1), expectedCommitTime);
        assertEq(registry.getCommitTimestamp(protocolId2), expectedCommitTime);
        assertEq(registry.getCommitTimestamp(protocolId3), 0);

        // Commit first protocol only
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(protocolId1);

        // Check that only first protocol is affected
        assertFalse(registry.hasQueuedConfig(protocolId1));
        assertTrue(registry.hasQueuedConfig(protocolId2));
        assertFalse(registry.hasQueuedConfig(protocolId3));

        assertEq(registry.getCommitTimestamp(protocolId1), 0);
        assertEq(registry.getCommitTimestamp(protocolId2), expectedCommitTime);
        assertEq(registry.getCommitTimestamp(protocolId3), 0);
    }

    function test_ViewFunctions_FuzzedProtocolId(bytes4 protocolId) external {
        // it works with any protocol ID

        // Initially should return default values
        assertFalse(registry.hasQueuedConfig(protocolId));
        assertEq(registry.getCommitTimestamp(protocolId), 0);

        vm.startPrank(owner);

        // Queue configuration
        uint64 queueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(protocolId, 0.15e18, feeReceiver);

        // Should return correct values
        assertTrue(registry.hasQueuedConfig(protocolId));
        assertEq(registry.getCommitTimestamp(protocolId), queueTime + registry.delayPeriod());

        vm.stopPrank();

        // Commit configuration
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(protocolId);

        // Should return default values again
        assertFalse(registry.hasQueuedConfig(protocolId));
        assertEq(registry.getCommitTimestamp(protocolId), 0);
    }
}
