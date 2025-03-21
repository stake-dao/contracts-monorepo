// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__shutdownProtocol is ProtocolControllerBaseTest {
    function test_RevertsIfCallerIsNotTheOwner(address caller) external {
        // it reverts if caller is not the owner

        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        vm.prank(caller);
        protocolController.shutdownProtocol(vm.randomBytes4());
    }

    function test_ShutsDownAProtocol(bytes4 protocolId) external {
        // it shuts down a protocol

        assertEq(protocolController.isShutdownProtocol(protocolId), false);

        protocolController.shutdownProtocol(protocolId);
        assertEq(protocolController.isShutdownProtocol(protocolId), true);
    }

    function test_EmitsAProtocolShutdownEvent(bytes4 protocolId) external {
        // it emits a ProtocolShutdown event

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolShutdown(protocolId);

        protocolController.shutdownProtocol(protocolId);
    }
}
