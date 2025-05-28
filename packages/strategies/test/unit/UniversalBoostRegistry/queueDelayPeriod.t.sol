// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__QueueDelayPeriod is Test {
    UniversalBoostRegistry internal registry;

    address internal owner;
    address internal nonOwner = makeAddr("nonOwner");

    event DelayPeriodQueued(uint64 newDelayPeriod, uint64 queuedTimestamp);

    function setUp() public {
        owner = makeAddr("owner");
        registry = new UniversalBoostRegistry(owner);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    modifier whenCallerIsNotOwner() {
        vm.startPrank(nonOwner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwner() external whenCallerIsNotOwner {
        // it reverts when caller is not owner

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        registry.queueDelayPeriod(2 days);
    }

    function test_QueueDelayPeriod_Success() external whenCallerIsOwner {
        // it queues the delay period successfully
        // it sets the queued delay period
        // it sets the queued timestamp
        // it emits DelayPeriodQueued event

        uint64 newDelayPeriod = 2 days;
        uint64 currentTime = uint64(block.timestamp);
        uint64 expectedQueuedTimestamp = currentTime + registry.delayPeriod();

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(newDelayPeriod, expectedQueuedTimestamp);

        registry.queueDelayPeriod(newDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), newDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedQueuedTimestamp);
        assertTrue(registry.hasQueuedDelayPeriod());
        assertEq(registry.getDelayPeriodCommitTimestamp(), expectedQueuedTimestamp);
    }

    function test_QueueDelayPeriod_OverwritesPreviousQueue() external whenCallerIsOwner {
        // it overwrites previously queued delay period

        uint64 firstDelayPeriod = 2 days;
        uint64 secondDelayPeriod = 3 days;

        // Queue first delay period
        registry.queueDelayPeriod(firstDelayPeriod);
        assertEq(registry.queuedDelayPeriod(), firstDelayPeriod);

        // Advance time slightly and queue second delay period
        vm.warp(block.timestamp + 1 hours);
        uint64 secondQueueTime = uint64(block.timestamp);
        uint64 expectedSecondTimestamp = secondQueueTime + registry.delayPeriod();

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(secondDelayPeriod, expectedSecondTimestamp);

        registry.queueDelayPeriod(secondDelayPeriod);

        // Should have updated to second values
        assertEq(registry.queuedDelayPeriod(), secondDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedSecondTimestamp);
    }

    function test_QueueDelayPeriod_UsesCurrentDelayPeriod() external whenCallerIsOwner {
        // it uses the current delay period for queue timestamp calculation

        uint64 originalDelayPeriod = registry.delayPeriod();
        uint64 newDelayPeriod = 3 days;

        uint64 queueTime = uint64(block.timestamp);
        registry.queueDelayPeriod(newDelayPeriod);

        // Should use original delay period, not the new one being queued
        uint64 expectedTimestamp = queueTime + originalDelayPeriod;
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedTimestamp);
    }

    function test_QueueDelayPeriod_ZeroDelayPeriod() external whenCallerIsOwner {
        // it allows queuing zero delay period

        uint64 zeroDelayPeriod = 0;
        uint64 currentTime = uint64(block.timestamp);
        uint64 expectedTimestamp = currentTime + registry.delayPeriod();

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(zeroDelayPeriod, expectedTimestamp);

        registry.queueDelayPeriod(zeroDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), zeroDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedTimestamp);
    }

    function test_QueueDelayPeriod_MaxDelayPeriod() external whenCallerIsOwner {
        // it allows queuing maximum delay period

        uint64 maxDelayPeriod = type(uint64).max;
        uint64 currentTime = uint64(block.timestamp);
        uint64 expectedTimestamp = currentTime + registry.delayPeriod();

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(maxDelayPeriod, expectedTimestamp);

        registry.queueDelayPeriod(maxDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), maxDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedTimestamp);
    }

    function test_QueueDelayPeriod_SameAsCurrentDelay() external whenCallerIsOwner {
        // it allows queuing the same delay period as current

        uint64 currentDelayPeriod = registry.delayPeriod();
        uint64 currentTime = uint64(block.timestamp);
        uint64 expectedTimestamp = currentTime + currentDelayPeriod;

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(currentDelayPeriod, expectedTimestamp);

        registry.queueDelayPeriod(currentDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), currentDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedTimestamp);
    }

    function test_QueueDelayPeriod_FuzzedDelayPeriod(uint64 newDelayPeriod) external whenCallerIsOwner {
        // it works with any delay period value

        uint64 currentTime = uint64(block.timestamp);
        uint64 expectedTimestamp = currentTime + registry.delayPeriod();

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(newDelayPeriod, expectedTimestamp);

        registry.queueDelayPeriod(newDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), newDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedTimestamp);
        assertTrue(registry.hasQueuedDelayPeriod());
        assertEq(registry.getDelayPeriodCommitTimestamp(), expectedTimestamp);
    }

    function test_QueueDelayPeriod_AfterCommit() external whenCallerIsOwner {
        // it allows queuing new delay period after previous one was committed

        uint64 firstDelayPeriod = 2 days;
        uint64 secondDelayPeriod = 3 days;

        // Queue and commit first delay period
        registry.queueDelayPeriod(firstDelayPeriod);
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitDelayPeriod();

        // Verify first delay period is now active
        assertEq(registry.delayPeriod(), firstDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());

        // Queue second delay period
        uint64 secondQueueTime = uint64(block.timestamp);
        uint64 expectedSecondTimestamp = secondQueueTime + firstDelayPeriod; // Uses new active delay

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodQueued(secondDelayPeriod, expectedSecondTimestamp);

        registry.queueDelayPeriod(secondDelayPeriod);

        assertEq(registry.queuedDelayPeriod(), secondDelayPeriod);
        assertEq(registry.delayPeriodQueuedTimestamp(), expectedSecondTimestamp);
        assertTrue(registry.hasQueuedDelayPeriod());
    }
}
