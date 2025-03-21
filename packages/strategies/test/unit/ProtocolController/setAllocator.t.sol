// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__setAllocator is ProtocolControllerBaseTest {
    function test_SetsTheAllocatorForAProtocol(bytes4 protocolId, address allocator) external {
        // it sets the allocator for a protocol

        vm.assume(allocator != address(0));

        vm.prank(owner);
        protocolController.setAllocator(protocolId, allocator);

        assertEq(protocolController.allocator(protocolId), allocator);
    }

    function test_EmitsTheUpdateEvent(bytes4 protocolId, address allocator) external {
        // it emits the update event

        vm.assume(allocator != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolComponentSet(protocolId, "Allocator", allocator);

        vm.prank(owner);
        protocolController.setAllocator(protocolId, allocator);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        protocolController.setAllocator(vm.randomBytes4(), makeAddr("allocator"));
    }

    function test_RevertsIfTheAllocatorIsTheZeroAddress() external {
        // it reverts if the allocator is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(owner);
        protocolController.setAllocator(vm.randomBytes4(), address(0));
    }
}
