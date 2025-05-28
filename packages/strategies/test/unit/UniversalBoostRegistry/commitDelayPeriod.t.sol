// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__CommitDelayPeriod is Test {
    UniversalBoostRegistry internal registry;

    address internal owner;
    address internal anyone = makeAddr("anyone");

    event DelayPeriodCommitted(uint64 newDelayPeriod, uint64 committedTimestamp);

    function setUp() public {
        owner = makeAddr("owner");
        registry = new UniversalBoostRegistry(owner);
    }

    modifier givenNoQueuedDelayPeriod() {
        // Ensure no delay period is queued
        assertFalse(registry.hasQueuedDelayPeriod());
        _;
    }

    modifier givenQueuedDelayPeriod() {
        vm.prank(owner);
        registry.queueDelayPeriod(2 days);
        _;
    }

    modifier givenDelayPeriodNotPassed() {
        // Ensure delay period has not passed
        assertTrue(uint64(block.timestamp) < registry.delayPeriodQueuedTimestamp());
        _;
    }

    modifier givenDelayPeriodPassed() {
        // Advance time so delay period has passed
        vm.warp(registry.delayPeriodQueuedTimestamp());
        _;
    }

    function test_RevertWhen_NoQueuedDelayPeriod() external givenNoQueuedDelayPeriod {
        // it reverts when no delay period is queued

        vm.expectRevert(UniversalBoostRegistry.NoQueuedDelayPeriod.selector);
        registry.commitDelayPeriod();
    }

    function test_RevertWhen_DelayPeriodNotPassed() external givenQueuedDelayPeriod givenDelayPeriodNotPassed {
        // it reverts when delay period has not passed

        vm.expectRevert(UniversalBoostRegistry.DelayPeriodNotPassed.selector);
        registry.commitDelayPeriod();
    }

    function test_CommitDelayPeriod_Success() external givenQueuedDelayPeriod givenDelayPeriodPassed {
        // it commits the delay period successfully
        // it updates the active delay period
        // it clears the queued values
        // it emits DelayPeriodCommitted event

        uint64 newDelayPeriod = registry.queuedDelayPeriod();
        uint64 currentTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(newDelayPeriod, currentTime);

        registry.commitDelayPeriod();

        // Check active delay period is updated
        assertEq(registry.delayPeriod(), newDelayPeriod);

        // Check queued values are cleared
        assertEq(registry.queuedDelayPeriod(), 0);
        assertEq(registry.delayPeriodQueuedTimestamp(), 0);
        assertFalse(registry.hasQueuedDelayPeriod());
        assertEq(registry.getDelayPeriodCommitTimestamp(), 0);
    }

    function test_CommitDelayPeriod_CanBeCalledByAnyone() external givenQueuedDelayPeriod givenDelayPeriodPassed {
        // it can be called by anyone, not just owner

        uint64 newDelayPeriod = registry.queuedDelayPeriod();
        uint64 currentTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(newDelayPeriod, currentTime);

        vm.prank(anyone);
        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), newDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_ExactlyAtDelayTime() external givenQueuedDelayPeriod {
        // it allows commit exactly at the delay timestamp

        uint64 queuedTimestamp = registry.delayPeriodQueuedTimestamp();
        uint64 newDelayPeriod = registry.queuedDelayPeriod();

        vm.warp(queuedTimestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(newDelayPeriod, queuedTimestamp);

        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), newDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_LongAfterDelayTime() external givenQueuedDelayPeriod {
        // it allows commit long after the delay timestamp

        uint64 queuedTimestamp = registry.delayPeriodQueuedTimestamp();
        uint64 newDelayPeriod = registry.queuedDelayPeriod();

        // Advance time way past the required delay
        vm.warp(queuedTimestamp + 365 days);
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(newDelayPeriod, commitTime);

        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), newDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_ZeroDelayPeriod() external {
        // it allows committing zero delay period

        vm.prank(owner);
        registry.queueDelayPeriod(0);

        vm.warp(registry.delayPeriodQueuedTimestamp());
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(0, commitTime);

        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), 0);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_MaxDelayPeriod() external {
        // it allows committing maximum delay period

        uint64 maxDelayPeriod = type(uint64).max;

        vm.prank(owner);
        registry.queueDelayPeriod(maxDelayPeriod);

        vm.warp(registry.delayPeriodQueuedTimestamp());
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(maxDelayPeriod, commitTime);

        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), maxDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_AfterRequeue() external {
        // it works correctly after requeuing different delay period

        vm.startPrank(owner);

        // Queue first delay period
        registry.queueDelayPeriod(2 days);
        uint64 firstDelayPeriod = registry.queuedDelayPeriod();

        // Requeue with different delay period before first is committed
        registry.queueDelayPeriod(3 days);
        uint64 secondDelayPeriod = registry.queuedDelayPeriod();

        vm.stopPrank();

        // Advance time and commit the second (latest) delay period
        vm.warp(registry.delayPeriodQueuedTimestamp());
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(secondDelayPeriod, commitTime);

        registry.commitDelayPeriod();

        // Should have committed the second delay period, not the first
        assertEq(registry.delayPeriod(), secondDelayPeriod);
        assertNotEq(registry.delayPeriod(), firstDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_FuzzedDelayPeriod(uint64 newDelayPeriod) external {
        // it works with any delay period value

        vm.prank(owner);
        registry.queueDelayPeriod(newDelayPeriod);

        vm.warp(registry.delayPeriodQueuedTimestamp());
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit DelayPeriodCommitted(newDelayPeriod, commitTime);

        registry.commitDelayPeriod();

        assertEq(registry.delayPeriod(), newDelayPeriod);
        assertFalse(registry.hasQueuedDelayPeriod());
    }

    function test_CommitDelayPeriod_MultipleCommits() external {
        // it allows multiple delay period changes over time

        vm.startPrank(owner);

        // First delay period change
        registry.queueDelayPeriod(2 days);
        vm.stopPrank();

        vm.warp(registry.delayPeriodQueuedTimestamp());
        registry.commitDelayPeriod();
        assertEq(registry.delayPeriod(), 2 days);

        // Second delay period change
        vm.prank(owner);
        registry.queueDelayPeriod(3 days);

        vm.warp(registry.delayPeriodQueuedTimestamp());
        registry.commitDelayPeriod();
        assertEq(registry.delayPeriod(), 3 days);

        // Third delay period change
        vm.prank(owner);
        registry.queueDelayPeriod(1 days);

        vm.warp(registry.delayPeriodQueuedTimestamp());
        registry.commitDelayPeriod();
        assertEq(registry.delayPeriod(), 1 days);
    }

    function test_RevertWhen_CommitAfterAlreadyCommitted() external givenQueuedDelayPeriod givenDelayPeriodPassed {
        // it reverts when trying to commit again after already committed

        // First commit should succeed
        registry.commitDelayPeriod();
        assertFalse(registry.hasQueuedDelayPeriod());

        // Second commit should revert
        vm.expectRevert(UniversalBoostRegistry.NoQueuedDelayPeriod.selector);
        registry.commitDelayPeriod();
    }
}
