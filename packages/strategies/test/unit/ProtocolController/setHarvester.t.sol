// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";

contract ProtocolController__setHarvester is ProtocolControllerBaseTest {
    function test_SetsTheHarvesterForAProtocol(bytes4 protocolId, address harvester) external {
        // it sets the harvester for a protocol

        vm.assume(harvester != address(0));

        vm.prank(owner);
        protocolController.setHarvester(protocolId, harvester);

        assertEq(protocolController.harvester(protocolId), harvester);
    }

    function test_EmitsTheUpdateEvent(bytes4 protocolId, address harvester) external {
        // it emits the update event

        vm.assume(harvester != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolComponentSet(protocolId, "Harvester", harvester);

        vm.prank(owner);
        protocolController.setHarvester(protocolId, harvester);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        protocolController.setHarvester(vm.randomBytes4(), makeAddr("harvester"));
    }

    function test_RevertsIfTheHarvesterIsTheZeroAddress() external {
        // it reverts if the harvester is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(owner);
        protocolController.setHarvester(vm.randomBytes4(), address(0));
    }
}
