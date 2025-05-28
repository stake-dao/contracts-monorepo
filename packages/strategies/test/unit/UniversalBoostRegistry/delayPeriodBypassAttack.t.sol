// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__DelayPeriodBypassAttack is Test {
    UniversalBoostRegistry internal registry;
    
    address internal owner;
    address internal feeReceiver = makeAddr("feeReceiver");
    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");

    function setUp() public {
        owner = makeAddr("owner");
        registry = new UniversalBoostRegistry(owner);
    }

    function test_PreventsBypassAttack_ReduceDelayThenQueueConfig() external {
        // it prevents bypass attack where owner reduces delay then queues config

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod(); // 1 day
        uint64 shorterDelay = 1 hours;

        // Attacker tries to reduce delay period
        registry.queueDelayPeriod(shorterDelay);
        
        // Verify delay period is queued but not active yet
        assertEq(registry.delayPeriod(), originalDelay); // Still original delay
        assertEq(registry.queuedDelayPeriod(), shorterDelay);
        assertTrue(registry.hasQueuedDelayPeriod());

        // Attacker tries to queue protocol config immediately
        // This should use the CURRENT delay period (originalDelay), not the queued one
        uint64 configQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.3e18);

        // Verify protocol config uses original delay period
        uint64 expectedProtocolCommitTime = configQueueTime + originalDelay;
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedProtocolCommitTime);

        vm.stopPrank();

        // Advance time to when shorter delay would have allowed commit (1 hour)
        vm.warp(block.timestamp + shorterDelay);

        // Protocol config should NOT be committable yet (because it uses original delay)
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Delay period should NOT be committable yet either
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitDelayPeriod();

        // Advance time to when original delay period allows commits
        vm.warp(block.timestamp + originalDelay - shorterDelay);

        // Now both can be committed
        registry.commitDelayPeriod();
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Verify the attack was prevented - took full original delay
        assertEq(registry.delayPeriod(), shorterDelay); // New delay is now active
        assertTrue(uint64(block.timestamp) >= configQueueTime + originalDelay);
    }

    function test_PreventsBypassAttack_QueueZeroDelayThenConfig() external {
        // it prevents bypass attack with zero delay period

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod(); // 1 day
        uint64 zeroDelay = 0;

        // Attacker tries to set zero delay
        registry.queueDelayPeriod(zeroDelay);

        // Immediately queue protocol config
        uint64 configQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.4e18);
        registry.setFeeReceiver(PROTOCOL_ID, feeReceiver);

        vm.stopPrank();

        // Config should still require original delay, not zero
        uint64 expectedCommitTime = configQueueTime + originalDelay;
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedCommitTime);

        // Cannot commit immediately
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Must wait full original delay
        vm.warp(expectedCommitTime);
        
        // Now can commit both
        registry.commitDelayPeriod();
        registry.commitProtocolConfig(PROTOCOL_ID);

        assertEq(registry.delayPeriod(), zeroDelay);
    }

    function test_PreventsBypassAttack_MultipleConfigChanges() external {
        // it prevents bypass even with multiple config changes

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod();
        uint64 shorterDelay = 2 hours;

        // Queue shorter delay
        registry.queueDelayPeriod(shorterDelay);

        // Queue multiple protocol configs immediately
        bytes4 protocol1 = bytes4(hex"11111111");
        bytes4 protocol2 = bytes4(hex"22222222");
        bytes4 protocol3 = bytes4(hex"33333333");

        uint64 queueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(protocol1, 0.1e18);
        registry.setFeeReceiver(protocol1, feeReceiver);
        registry.queueNewProtocolConfig(protocol2, 0.2e18);
        registry.setFeeReceiver(protocol2, feeReceiver);
        registry.queueNewProtocolConfig(protocol3, 0.3e18);
        registry.setFeeReceiver(protocol3, feeReceiver);

        vm.stopPrank();

        // All configs should use original delay
        uint64 expectedCommitTime = queueTime + originalDelay;
        assertEq(registry.getCommitTimestamp(protocol1), expectedCommitTime);
        assertEq(registry.getCommitTimestamp(protocol2), expectedCommitTime);
        assertEq(registry.getCommitTimestamp(protocol3), expectedCommitTime);

        // Advance to shorter delay time - none should be committable
        vm.warp(block.timestamp + shorterDelay);

        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(protocol1);
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(protocol2);
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(protocol3);

        // Advance to full original delay
        vm.warp(expectedCommitTime);

        // Now all can be committed
        registry.commitDelayPeriod();
        registry.commitProtocolConfig(protocol1);
        registry.commitProtocolConfig(protocol2);
        registry.commitProtocolConfig(protocol3);
    }

    function test_SecureWorkflow_DelayChangeAfterCommit() external {
        // it allows secure workflow where delay is changed first, then configs use new delay

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod();
        uint64 newDelay = 2 days;

        // Step 1: Queue new delay period
        registry.queueDelayPeriod(newDelay);

        vm.stopPrank();

        // Step 2: Wait for delay period to pass and commit
        vm.warp(block.timestamp + originalDelay);
        registry.commitDelayPeriod();

        // Step 3: Now new delay is active
        assertEq(registry.delayPeriod(), newDelay);
        assertFalse(registry.hasQueuedDelayPeriod());

        // Step 4: Queue protocol config - should use NEW delay period
        vm.startPrank(owner);
        uint64 configQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.25e18);
        registry.setFeeReceiver(PROTOCOL_ID, feeReceiver);
        vm.stopPrank();

        // Should use new delay period
        uint64 expectedCommitTime = configQueueTime + newDelay;
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedCommitTime);

        // Advance to new delay time and commit
        vm.warp(expectedCommitTime);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Verify config was committed with new delay
        (uint128 fees,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(fees, 0.25e18);
    }

    function test_PreventsBypassAttack_FuzzedDelays(uint64 shorterDelay) external {
        // it prevents bypass attack with any shorter delay value

        vm.assume(shorterDelay < registry.delayPeriod());

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod();

        // Queue shorter delay
        registry.queueDelayPeriod(shorterDelay);

        // Queue protocol config
        uint64 configQueueTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.35e18);
        registry.setFeeReceiver(PROTOCOL_ID, feeReceiver);

        vm.stopPrank();

        // Config should use original delay, not shorter delay
        uint64 expectedCommitTime = configQueueTime + originalDelay;
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedCommitTime);

        // Cannot commit at shorter delay time
        if (shorterDelay > 0) {
            vm.warp(block.timestamp + shorterDelay);
            vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
            registry.commitProtocolConfig(PROTOCOL_ID);
        }

        // Must wait for full original delay
        vm.warp(expectedCommitTime);
        registry.commitDelayPeriod();
        registry.commitProtocolConfig(PROTOCOL_ID);
    }

    function test_PreventsBypassAttack_RepeatedAttempts() external {
        // it prevents bypass even with repeated attempts

        vm.startPrank(owner);

        uint64 originalDelay = registry.delayPeriod();

        // First attempt: queue short delay and config
        registry.queueDelayPeriod(1 hours);
        uint64 firstConfigTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18);
        registry.setFeeReceiver(PROTOCOL_ID, feeReceiver);

        // Second attempt: queue even shorter delay and update config
        vm.warp(block.timestamp + 30 minutes);
        registry.queueDelayPeriod(30 minutes);
        uint64 secondConfigTime = uint64(block.timestamp);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.2e18);
        registry.setFeeReceiver(PROTOCOL_ID, feeReceiver);

        vm.stopPrank();

        // Latest config should still use original delay from when it was queued
        uint64 expectedCommitTime = secondConfigTime + originalDelay;
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), expectedCommitTime);

        // Cannot commit early
        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Must wait full delay from second config queue time
        vm.warp(expectedCommitTime);
        registry.commitDelayPeriod(); // Commit the 30 minute delay
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Verify the second config was applied
        (uint128 fees,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(fees, 0.2e18);
        assertEq(registry.delayPeriod(), 30 minutes);
    }
}