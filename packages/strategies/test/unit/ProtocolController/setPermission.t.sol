// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {ProtocolControllerHarness} from "test/unit/ProtocolController/ProtocolControllerHarness.t.sol";

contract ProtocolController__setPermission is ProtocolControllerBaseTest {
    function test_SetsThePermissionForAContractCallerAndFunctionSelector(
        address _contract,
        address caller,
        bytes4 selector,
        bool allowed
    ) external {
        // it sets the permission for a contract, caller, and function selector

        vm.assume(_contract != address(0));
        vm.assume(caller != address(0));

        ProtocolControllerHarness protocolControllerHarness = _deployProtocolControllerHarness();

        vm.prank(owner);
        protocolControllerHarness.setPermission(_contract, caller, selector, allowed);

        assertEq(protocolControllerHarness._exposed_permissions(_contract, caller, selector), allowed);
    }

    function test_EmitsAPermissionSetEvent(address _contract, address caller, bytes4 selector, bool allowed) external {
        // it emit a permission set event

        vm.assume(_contract != address(0));
        vm.assume(caller != address(0));

        ProtocolControllerHarness protocolControllerHarness = _deployProtocolControllerHarness();

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.PermissionSet(_contract, caller, selector, allowed);

        vm.prank(owner);
        protocolControllerHarness.setPermission(_contract, caller, selector, allowed);
    }

    function test_RevertsIfTheSenderIsNotAuthorized(address caller) external {
        // it reverts if the sender is not authorized

        vm.assume(caller != owner);
        vm.assume(protocolController.permissionSetters(caller) == false);

        vm.expectRevert(abi.encodeWithSelector(ProtocolController.NotPermissionSetter.selector));

        vm.prank(caller);
        protocolController.setPermission(makeAddr("contract"), makeAddr("caller"), vm.randomBytes4(), true);
    }

    function test_RevertsIfTheContractIsTheZeroAddress() external {
        // it reverts if the contract is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);

        vm.prank(owner);
        protocolController.setPermission(address(0), makeAddr("caller"), vm.randomBytes4(), true);
    }

    function test_RevertsIfTheCallerIsTheZeroAddress() external {
        // it reverts if the caller is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);

        vm.prank(owner);
        protocolController.setPermission(makeAddr("contract"), address(0), vm.randomBytes4(), true);
    }
}
