// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Test} from "forge-std/src/Test.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

contract UniversalBoostRegistry__QueueNewProtocolConfig is Test {
    UniversalBoostRegistry internal registry;

    bytes4 internal constant PROTOCOL_ID = bytes4(hex"12345678");
    address internal owner;
    address internal nonOwner = makeAddr("nonOwner");
    address internal feeReceiver = makeAddr("feeReceiver");

    function setUp() public {
        registry = new UniversalBoostRegistry(makeAddr("initialOwner"));
        owner = registry.owner();
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it reverts with OwnableUnauthorizedAccount

        vm.startPrank(nonOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18);

        vm.stopPrank();
    }

    function test_RevertWhen_ProtocolFeeExceedsMaximum() external {
        // it reverts with FeeExceedsMaximum

        vm.startPrank(owner);

        uint128 maxFee = registry.MAX_FEE_PERCENT();
        uint128 excessiveFee = maxFee + 1;

        vm.expectRevert(abi.encodeWithSelector(UniversalBoostRegistry.FeeExceedsMaximum.selector));
        registry.queueNewProtocolConfig(PROTOCOL_ID, excessiveFee);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_ValidParameters() external {
        // it updates the queued configuration
        // it preserves active configuration (if any)
        // it emits NewProtocolConfigQueued event

        vm.startPrank(owner);

        uint128 protocolFees = 0.15e18;
        uint64 queueTimestamp = uint64(block.timestamp) + registry.delayPeriod();

        // Expect the NewProtocolConfigQueued event
        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.NewProtocolConfigQueued(PROTOCOL_ID, protocolFees, queueTimestamp);

        // Queue new configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, protocolFees);

        // Check the queued configuration
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        // Active configuration should remain unchanged (zero)
        assertEq(activeProtocolFees, 0);
        assertEq(activeFeeReceiver, address(0));
        assertEq(lastUpdated, 0);

        // Queued configuration should be set
        assertEq(queuedProtocolFees, protocolFees);
        assertEq(queuedTimestamp, queueTimestamp);

        // View functions should reflect the queued state
        assertTrue(registry.hasQueuedConfig(PROTOCOL_ID));
        assertEq(registry.getCommitTimestamp(PROTOCOL_ID), queueTimestamp);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_OverwritesPreviousQueue() external {
        // it overwrites a previously queued configuration

        vm.startPrank(owner);

        uint128 firstFee = 0.1e18;

        uint128 secondFee = 0.2e18;

        // Queue first configuration
        registry.queueNewProtocolConfig(PROTOCOL_ID, firstFee);

        // Advance time slightly
        skip(1 hours);
        uint64 secondQueueTime = uint64(block.timestamp) + registry.delayPeriod();

        // Queue second configuration (should overwrite first)
        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.NewProtocolConfigQueued(PROTOCOL_ID, secondFee, secondQueueTime);

        registry.queueNewProtocolConfig(PROTOCOL_ID, secondFee);

        // Check that second configuration overwrote first
        (, uint128 queuedProtocolFees,, uint64 queuedTimestamp,) = registry.protocolConfig(PROTOCOL_ID);

        assertEq(queuedProtocolFees, secondFee);
        assertEq(queuedTimestamp, secondQueueTime);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_PreservesActiveConfig() external {
        // it preserves existing active configuration when queuing

        vm.startPrank(owner);

        // First, set up an active configuration by queuing and committing
        uint128 activeFee = 0.1e18;

        registry.queueNewProtocolConfig(PROTOCOL_ID, activeFee);

        // Set fee receiver separately
        registry.setFeeReceiver(PROTOCOL_ID, makeAddr("activeReceiver"));

        // Advance time past delay period and commit
        skip(registry.delayPeriod() + 1);
        registry.commitProtocolConfig(PROTOCOL_ID);

        // Now queue a new configuration
        uint128 newFee = 0.25e18;
        uint64 newQueueTime = uint64(block.timestamp) + registry.delayPeriod();

        registry.queueNewProtocolConfig(PROTOCOL_ID, newFee);

        // Check that active configuration is preserved
        (
            uint128 activeProtocolFees,
            uint128 queuedProtocolFees,
            uint64 lastUpdated,
            uint64 queuedTimestamp,
            address activeFeeReceiver
        ) = registry.protocolConfig(PROTOCOL_ID);

        // Active values should remain unchanged
        assertEq(activeProtocolFees, activeFee);
        assertEq(activeFeeReceiver, makeAddr("activeReceiver"));
        assertGt(lastUpdated, 0);

        // Queued values should be the new ones
        assertEq(queuedProtocolFees, newFee);
        assertEq(queuedTimestamp, newQueueTime);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_AtMaximumFee() external {
        // it allows setting fee to maximum allowed value

        vm.startPrank(owner);

        uint128 maxFee = registry.MAX_FEE_PERCENT();

        // Should succeed with maximum fee
        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.NewProtocolConfigQueued(
            PROTOCOL_ID, maxFee, uint64(block.timestamp) + registry.delayPeriod()
        );

        registry.queueNewProtocolConfig(PROTOCOL_ID, maxFee);

        // Check configuration was set
        (, uint128 queuedProtocolFees,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(queuedProtocolFees, maxFee);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_ZeroFee() external {
        // it allows setting fee to zero

        vm.startPrank(owner);

        uint128 zeroFee = 0;

        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.NewProtocolConfigQueued(
            PROTOCOL_ID, zeroFee, uint64(block.timestamp) + registry.delayPeriod()
        );

        registry.queueNewProtocolConfig(PROTOCOL_ID, zeroFee);

        // Check configuration was set
        (, uint128 queuedProtocolFees,,,) = registry.protocolConfig(PROTOCOL_ID);
        assertEq(queuedProtocolFees, zeroFee);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_FuzzedParameters(bytes4 protocolId, uint128 protocolFees) external {
        // it works with valid fuzzed parameters

        // Bound the fee to valid range
        protocolFees = uint128(bound(protocolFees, 0, registry.MAX_FEE_PERCENT()));

        vm.startPrank(owner);

        vm.expectEmit(true, false, false, true);
        emit UniversalBoostRegistry.NewProtocolConfigQueued(
            protocolId, protocolFees, uint64(block.timestamp) + registry.delayPeriod()
        );

        registry.queueNewProtocolConfig(protocolId, protocolFees);

        // Check configuration was set
        (, uint128 queuedProtocolFees,,,) = registry.protocolConfig(protocolId);
        assertEq(queuedProtocolFees, protocolFees);

        assertTrue(registry.hasQueuedConfig(protocolId));
        assertEq(registry.getCommitTimestamp(protocolId), uint64(block.timestamp) + registry.delayPeriod());

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_DoesNotAffectOtherProtocols() external {
        // it does not affect configurations of other protocols

        bytes4 otherProtocolId = bytes4(hex"87654321");

        vm.startPrank(owner);

        // Queue configuration for first protocol
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18);

        // Check that other protocol remains unaffected
        (
            uint128 otherActiveProtocolFees,
            uint128 otherQueuedProtocolFees,
            uint64 otherLastUpdated,
            uint64 otherQueuedTimestamp,
            address otherActiveFeeReceiver
        ) = registry.protocolConfig(otherProtocolId);

        assertEq(otherActiveProtocolFees, 0);
        assertEq(otherQueuedProtocolFees, 0);
        assertEq(otherLastUpdated, 0);
        assertEq(otherQueuedTimestamp, 0);
        assertEq(otherActiveFeeReceiver, address(0));

        assertFalse(registry.hasQueuedConfig(otherProtocolId));
        assertEq(registry.getCommitTimestamp(otherProtocolId), 0);

        vm.stopPrank();
    }

    function test_QueueNewProtocolConfig_DoesNotAffectRentals() external {
        // it does not affect boost rental status

        address user = makeAddr("user");

        // User rents boost
        vm.prank(user);
        registry.rentBoost(PROTOCOL_ID);
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));

        // Owner queues configuration
        vm.prank(owner);
        registry.queueNewProtocolConfig(PROTOCOL_ID, 0.1e18);

        // Rental status should remain unchanged
        assertTrue(registry.isRentingBoost(user, PROTOCOL_ID));
    }
}
