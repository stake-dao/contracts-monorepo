// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__CommitProtocolConfig is Test {
    UniversalBoostRegistry internal registry;

    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");
    address internal owner;
    address internal nonOwner = makeAddr("nonOwner");
    address internal feeReceiver = makeAddr("feeReceiver");

    function setUp() public {
        registry = new UniversalBoostRegistry();
        owner = registry.owner();
    }

    function test_RevertWhen_NoQueuedConfig() external {
        // it reverts with NoQueuedConfig when no configuration is queued

        vm.expectRevert(abi.encodeWithSelector(UniversalBoostRegistry.NoQueuedConfig.selector));
        registry.commitProtocolConfig(PROTOCOL_ID);
    }

    function test_RevertWhen_DelayPeriodNotPassed() external {
        // it reverts with DelayPeriodNotPassed when delay period hasn't elapsed

        vm.startPrank(owner);

        // Queue a configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);

        vm.stopPrank();

        // Try to commit immediately (should fail)
        vm.expectRevert(abi.encodeWithSelector(UniversalBoostRegistry.DelayPeriodNotPassed.selector));
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Try to commit just before delay period ends (should still fail)
        skip(registry.delayPeriod() - 1);
        vm.expectRevert(abi.encodeWithSelector(UniversalBoostRegistry.DelayPeriodNotPassed.selector));
        registry.commitProtocolConfig(PROTOCOL_ID);
    }

    function test_CommitProtocolConfig_AfterDelayPeriod() external {
        // it commits the configuration after delay period
        // it moves queued values to active values
        // it clears queued values
        // it emits ProtocolConfigCommitted event

        vm.startPrank(owner);

        uint128 protocolFees = 0.15e18;

        // Queue a configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, protocolFees, feeReceiver);

        vm.stopPrank();

        // Advance time past delay period
        vm.warp(block.timestamp + registry.delayPeriod());
        uint64 commitTime = uint64(block.timestamp);

        // Expect the ProtocolConfigCommitted event
        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.ProtocolConfigCommitted(PROTOCOL_ID, protocolFees, feeReceiver, commitTime);

        // Commit the configuration
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check the final state
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver,
            address queuedFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        // Active values should be the committed ones
        assertEq(activeProtocolFees, protocolFees);
        assertEq(activeFeeReceiver, feeReceiver);
        assertEq(lastUpdated, commitTime);

        // Queued values should be cleared
        assertEq(queuedProtocolFees, 0);
        assertEq(queuedFeeReceiver, address(0));
        assertEq(queuedTimestamp, 0);

        // View functions should reflect the committed state
        assertFalse(registry.hasQueuedConfig(PROTOCOL_ID));
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), 0);
    }

    function test_CommitProtocolConfig_ExactlyAtDelayPeriod() external {
        // it allows committing exactly when delay period ends

        vm.startPrank(owner);

        uint128 protocolFees = 0.15e18;

        // Queue a configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, protocolFees, feeReceiver);

        vm.stopPrank();

        // Advance time to exactly delay period
        vm.warp(block.timestamp + registry.delayPeriod());

        // Should succeed
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that configuration was committed
        (uint128 activeProtocolFees,,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(activeProtocolFees, protocolFees);
    }

    function test_CommitProtocolConfig_WellAfterDelayPeriod() external {
        // it allows committing well after delay period

        vm.startPrank(owner);

        uint128 protocolFees = 0.15e18;

        // Queue a configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, protocolFees, feeReceiver);

        vm.stopPrank();

        // Advance time well past delay period
        vm.warp(block.timestamp + registry.delayPeriod() + 30 days);

        // Should still succeed
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that configuration was committed
        (uint128 activeProtocolFees,,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(activeProtocolFees, protocolFees);
    }

    function test_CommitProtocolConfig_CanBeCalledByAnyone() external {
        // it allows any address to commit after delay period

        vm.startPrank(owner);

        // Queue a configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);

        vm.stopPrank();

        // Advance time past delay period
        vm.warp(block.timestamp + registry.delayPeriod());

        // Non-owner should be able to commit
        vm.prank(nonOwner);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that configuration was committed
        (uint128 activeProtocolFees,,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(activeProtocolFees, 0.15e18);
    }

    function test_CommitProtocolConfig_OverwritesExistingActive() external {
        // it overwrites existing active configuration

        vm.startPrank(owner);

        uint128 firstFee = 0.1e18;
        address firstReceiver = makeAddr("firstReceiver");

        // Set up first active configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, firstFee, firstReceiver);
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Queue and commit second configuration
        uint128 secondFee = 0.25e18;
        address secondReceiver = makeAddr("secondReceiver");

        registry.queueNewProtocolConfig(PROTOCOL_ID, secondFee, secondReceiver);
        vm.warp(block.timestamp + registry.delayPeriod());

        vm.stopPrank();

        uint64 secondCommitTime = uint64(block.timestamp);

        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.ProtocolConfigCommitted(PROTOCOL_ID, secondFee, secondReceiver, secondCommitTime);

        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that second configuration overwrote first
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver,
            address queuedFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        assertEq(activeProtocolFees, secondFee);
        assertEq(activeFeeReceiver, secondReceiver);
        assertEq(lastUpdated, secondCommitTime);

        // Queued values should be cleared
        assertEq(queuedProtocolFees, 0);
        assertEq(queuedFeeReceiver, address(0));
        assertEq(queuedTimestamp, 0);
    }

    function test_CommitProtocolConfig_ZeroValues() external {
        // it handles zero fee and zero address receiver

        vm.startPrank(owner);

        uint128 zeroFee = 0;
        address zeroReceiver = address(0);

        // Queue configuration with zero values
        registry.queueNewProtocolConfig(PROTOCOL_ID, zeroFee, zeroReceiver);

        vm.stopPrank();

        // Advance time and commit
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that zero values were committed correctly
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver,
            address queuedFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        assertEq(activeProtocolFees, zeroFee);
        assertEq(activeFeeReceiver, zeroReceiver);
        assertGt(lastUpdated, 0);

        // Queued values should be cleared
        assertEq(queuedProtocolFees, 0);
        assertEq(queuedFeeReceiver, address(0));
        assertEq(queuedTimestamp, 0);
    }

    function test_CommitProtocolConfig_MaximumFee() external {
        // it handles maximum fee value

        vm.startPrank(owner);

        uint128 maxFee = registry.MAX_FEE_PERCENT();

        // Queue configuration with maximum fee
        registry.queueNewProtocolConfig(PROTOCOL_ID, maxFee, feeReceiver);

        vm.stopPrank();

        // Advance time and commit
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Check that maximum fee was committed correctly
        (uint128 activeProtocolFees,,,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(activeProtocolFees, maxFee);
    }

    function test_CommitProtocolConfig_MultipleProtocols() external {
        // it handles commits for multiple protocols independently

        bytes4 protocolId1 = bytes4(hex"11111111");
        bytes4 protocolId2 = bytes4(hex"22222222");

        uint128 fee1 = 0.1e18;
        uint128 fee2 = 0.2e18;
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        vm.startPrank(owner);

        // Queue configurations for both protocols
        registry.queueNewProtocolConfig(protocolId1, fee1, receiver1);
        registry.queueNewProtocolConfig(protocolId2, fee2, receiver2);

        vm.stopPrank();

        // Advance time and commit first protocol only
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(protocolId1);

        // Check first protocol was committed
        (uint128 active1,,,,,) = registry.protocolConfig(protocolId1);
        assertEq(active1, fee1);
        assertFalse(registry.hasQueuedConfig(protocolId1));

        // Check second protocol still queued
        (, uint128 queued2,,,,) = registry.protocolConfig(protocolId2);
        assertEq(queued2, fee2);
        assertTrue(registry.hasQueuedConfig(protocolId2));

        // Commit second protocol
        registry.commitProtocolConfig(protocolId2);

        // Check second protocol was committed
        (uint128 active2,,,,,) = registry.protocolConfig(protocolId2);
        assertEq(active2, fee2);
        assertFalse(registry.hasQueuedConfig(protocolId2));
    }

    function test_CommitProtocolConfig_DoesNotAffectRentals() external {
        // it does not affect boost rental status

        address user = makeAddr("user");

        // User rents boost
        vm.prank(user);
        registry.rentBoost(PROTOCOL_ID);
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        // Queue and commit configuration
        vm.startPrank(owner);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.15e18, feeReceiver);
        vm.warp(block.timestamp + registry.delayPeriod());
        registry.commitProtocolConfig(PROTOCOL_ID);
        vm.stopPrank();

        // Rental status should remain unchanged
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));
    }

    function test_CommitProtocolConfig_FuzzedParameters(bytes4 protocolId, uint128 protocolFees, address receiver)
        external
    {
        // it works with valid fuzzed parameters

        // Bound the fee to valid range
        protocolFees = uint128(bound(protocolFees, 0, registry.MAX_FEE_PERCENT()));

        vm.startPrank(owner);

        // Queue configuration
        registry.queueNewProtocolConfig(protocolId, protocolFees, receiver);

        vm.stopPrank();

        // Advance time and commit
        vm.warp(block.timestamp + registry.delayPeriod());
        uint64 commitTime = uint64(block.timestamp);

        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.ProtocolConfigCommitted(protocolId, protocolFees, receiver, commitTime);

        registry.commitProtocolConfig(protocolId);

        // Check configuration was committed correctly
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver,
            address queuedFeeReceiver
        ) = registry.protocolConfig(protocolId);

        assertEq(activeProtocolFees, protocolFees);
        assertEq(activeFeeReceiver, receiver);
        assertEq(lastUpdated, commitTime);

        // Queued values should be cleared
        assertEq(queuedProtocolFees, 0);
        assertEq(queuedFeeReceiver, address(0));
        assertEq(queuedTimestamp, 0);

        assertFalse(registry.hasQueuedConfig(protocolId));
        assertEq(registry.getCommitTimestamp(protocolId), 0);
    }
}
