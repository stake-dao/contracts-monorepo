// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";

contract ProtocolController__setAccountant is ProtocolControllerBaseTest {
    function test_SetsTheAccountantForAProtocol(bytes4 protocolId, address feeReceiver) external {
        // it sets the accountant for a protocol

        vm.assume(feeReceiver != address(0));

        // set the accountant
        vm.prank(owner);
        protocolController.setAccountant(protocolId, feeReceiver);

        // check the accountant is set
        assertEq(protocolController.accountant(protocolId), feeReceiver);
    }

    function test_EmitsTheUpdateEvent(bytes4 protocolId, address feeReceiver) external {
        // it emits the update event

        vm.assume(feeReceiver != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolComponentSet(protocolId, "Accountant", feeReceiver);

        vm.prank(owner);
        protocolController.setAccountant(protocolId, feeReceiver);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        protocolController.setAccountant(vm.randomBytes4(), makeAddr("accountant"));
    }

    function test_RevertsIfTheAccountantIsTheZeroAddress() external {
        // it reverts if the accountant is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(address(this));
        protocolController.setAccountant(vm.randomBytes4(), address(0));
    }
}
