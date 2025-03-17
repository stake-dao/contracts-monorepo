// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract ProtocolController__setPermissionSetter is ProtocolControllerBaseTest {
    function test_SetsThePermissionSetterForAProtocol(address setter) external {
        // it sets the permission setter for a protocol

        vm.assume(setter != address(0));

        assertEq(protocolController.permissionSetters(setter), false);

        vm.prank(owner);
        protocolController.setPermissionSetter(setter, true);

        assertEq(protocolController.permissionSetters(setter), true);
    }

    function test_EmitsAPermissionSetterSetEvent(address setter) external {
        // it emits a PermissionSetterSet event

        vm.assume(setter != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.PermissionSetterSet(setter, true);

        vm.prank(owner);
        protocolController.setPermissionSetter(setter, true);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner
        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        vm.prank(caller);
        protocolController.setPermissionSetter(makeAddr("setter"), true);
    }

    function test_RevertsIfThePermissionSetterIsTheZeroAddress() external {
        // it reverts if the permission setter is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);

        vm.prank(owner);
        protocolController.setPermissionSetter(address(0), true);
    }
}
