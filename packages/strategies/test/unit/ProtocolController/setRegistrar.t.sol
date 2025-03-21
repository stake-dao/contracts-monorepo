// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__setRegistrar is ProtocolControllerBaseTest {
    function test_SetsTheRegistrarForAProtocol(address registrar) external {
        // it sets the registrar for a protocol

        vm.assume(registrar != address(0));

        assertEq(protocolController.registrar(registrar), false);

        vm.prank(owner);
        protocolController.setRegistrar(registrar, true);

        assertEq(protocolController.registrar(registrar), true);
    }

    function test_EmitsARegistrarPermissionSetEvent(address registrar) external {
        // it emits a RegistrarPermissionSet event

        vm.assume(registrar != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.RegistrarPermissionSet(registrar, true);

        vm.prank(owner);
        protocolController.setRegistrar(registrar, true);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        vm.prank(caller);
        protocolController.setRegistrar(makeAddr("registrar"), true);
    }

    function test_RevertsIfTheRegistrarIsTheZeroAddress() external {
        // it reverts if the registrar is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);

        vm.prank(owner);
        protocolController.setRegistrar(address(0), true);
    }
}
