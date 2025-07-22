// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

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

        vm.assume(gauge != address(0));

        protocolController.registerVault({
            gauge_: gauge,
            vault: address(vault),
            asset: address(stakingToken),
            rewardReceiver: address(this),
            protocolId: protocolId
        });

        assertEq(protocolController.isShutdown(gauge), false);
        protocolController.shutdown(gauge);
        assertEq(protocolController.isShutdown(gauge), true);
    }

    function test_EmitsAGaugeShutdownEvent(address gauge) external {
        vm.assume(gauge != address(0));

        protocolController.registerVault({
            gauge_: gauge,
            vault: address(vault),
            asset: address(stakingToken),
            rewardReceiver: address(this),
            protocolId: protocolId
        });

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.GaugeShutdown(gauge);

        protocolController.shutdown(gauge);
    }
}
