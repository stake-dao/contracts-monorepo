// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__setFeeReceiver is ProtocolControllerBaseTest {
    function test_SetsTheFeeReceiverForAProtocol(bytes4 protocolId, address feeReceiver) external {
        // it sets the fee receiver for a protocol

        vm.assume(feeReceiver != address(0));

        vm.prank(owner);
        protocolController.setFeeReceiver(protocolId, feeReceiver);

        assertEq(protocolController.feeReceiver(protocolId), feeReceiver);
    }

    function test_EmitsTheUpdateEvent(bytes4 protocolId, address feeReceiver) external {
        // it emits the update event

        vm.assume(feeReceiver != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolComponentSet(protocolId, "FeeReceiver", feeReceiver);

        vm.prank(owner);
        protocolController.setFeeReceiver(protocolId, feeReceiver);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        protocolController.setFeeReceiver(vm.randomBytes4(), makeAddr("feeReceiver"));
    }

    function test_RevertsIfTheFeeReceiverIsTheZeroAddress() external {
        // it reverts if the fee receiver is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(owner);
        protocolController.setFeeReceiver(vm.randomBytes4(), address(0));
    }
}
