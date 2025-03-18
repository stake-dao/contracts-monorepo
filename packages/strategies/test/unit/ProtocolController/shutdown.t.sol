// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract ProtocolController__shutdown is ProtocolControllerBaseTest {
    function test_RevertsIfCallerIsNotTheOwner(address caller) external {
        // it reverts if caller is not the owner

        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        vm.prank(caller);
        protocolController.shutdown(makeAddr("gauge"));
    }

    function test_ShutsDownAGauge(address gauge) external {
        // it shuts down a gauge

        assertEq(protocolController.isShutdown(gauge), false);
        protocolController.shutdown(gauge);
        assertEq(protocolController.isShutdown(gauge), true);
    }

    function test_EmitsAGaugeShutdownEvent(address gauge) external {
        // it emits a GaugeShutdown event

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.GaugeShutdown(gauge);

        protocolController.shutdown(gauge);
    }
}
