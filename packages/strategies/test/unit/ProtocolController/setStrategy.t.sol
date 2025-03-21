// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__setStrategy is ProtocolControllerBaseTest {
    function test_SetsTheStrategyForAProtocol(bytes4 protocolId, address strategy) external {
        // it sets the strategy for a protocol

        vm.assume(strategy != address(0));

        protocolController.setStrategy(protocolId, strategy);
        assertEq(protocolController.strategy(protocolId), strategy);
    }

    function test_EmitsAProtocolComponentSetEvent(address strategy) external {
        // it emits a ProtocolComponentSet event

        vm.assume(strategy != address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.ProtocolComponentSet(protocolId, "Strategy", strategy);

        protocolController.setStrategy(protocolId, strategy);
    }

    function test_RevertsIfTheSenderIsNotTheOwner(address caller) external {
        // it reverts if the sender is not the owner

        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        vm.prank(caller);
        protocolController.setStrategy(protocolId, makeAddr("strategy"));
    }

    function test_RevertsIfTheStrategyIsTheZeroAddress() external {
        // it reverts if the strategy is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);

        vm.prank(owner);
        protocolController.setStrategy(vm.randomBytes4(), address(0));
    }
}
