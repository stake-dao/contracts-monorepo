// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {MockAccountant, ProtocolContextBaseTest, MockModuleManager} from "test/ProtocolContextBaseTest.t.sol";
import {ProtocolContextHarness} from "test/unit/ProtocolContext/ProtocolContextHarness.t.sol";

contract ProtocolContext__constructor is ProtocolContextBaseTest {
    function test_ExecutesOnTheGivenTargetIfLockerEqualsGateway(address target, bytes memory data) external {
        // it executes on the given target if locker equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        vm.expectCall(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector, target, 0, data, IModuleManager.Operation.Call
            ),
            1
        );

        new ProtocolContextHarness(protocolId, protocolController, address(0), gateway)._expose_executeTransaction(
            target, data
        );
    }

    function test_ReturnsTheSuccessOfTheTransactionIfLockerEqualsGateway(bool success) external {
        // it returns the success of the transaction if locker equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        vm.mockCall(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector,
                makeAddr("target"),
                0,
                abi.encode(0x1212),
                IModuleManager.Operation.Call
            ),
            abi.encode(success)
        );

        bool result = new ProtocolContextHarness(protocolId, protocolController, address(0), gateway)
            ._expose_executeTransaction(makeAddr("target"), abi.encode(0x1212));

        assertEq(result, success);
    }

    function test_RevertIfTheTransactionRevertsIfLockerEqualsGateway(address target, bytes memory data) external {
        // it revert if the transaction reverts if locker equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        ProtocolContextHarness protocolContextHarness =
            new ProtocolContextHarness(protocolId, protocolController, address(0), gateway);

        vm.mockCallRevert(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector, target, 0, data, IModuleManager.Operation.Call
            ),
            "UNEXPECTED_REVERT"
        );

        vm.expectRevert("UNEXPECTED_REVERT");
        protocolContextHarness._expose_executeTransaction(target, data);
    }

    function test_ExecutesOnTheLockerIfLockerNotEqualsGateway(address target, address locker, bytes memory data)
        external
    {
        // it executes on the locker if locker not equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.assume(address(locker) != address(0));
        vm.assume(address(locker) != gateway);
        vm.label({account: address(locker), newLabel: "Locker"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        ProtocolContextHarness protocolContextHarness =
            new ProtocolContextHarness(protocolId, protocolController, address(locker), gateway);

        vm.expectCall(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector,
                locker,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                IModuleManager.Operation.Call
            ),
            1
        );

        protocolContextHarness._expose_executeTransaction(target, data);
    }

    function test_ReturnsTheSuccessOfTheTransactionIfLockerNotEqualsGateway(
        address target,
        bytes memory data,
        bool success
    ) external {
        // it returns the success of the transaction if locker not equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.assume(address(locker) != address(0));
        vm.assume(address(locker) != gateway);
        vm.label({account: address(locker), newLabel: "Locker"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        ProtocolContextHarness protocolContextHarness =
            new ProtocolContextHarness(protocolId, protocolController, address(locker), gateway);

        vm.mockCall(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector,
                locker,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                IModuleManager.Operation.Call
            ),
            abi.encode(success)
        );

        bool result = protocolContextHarness._expose_executeTransaction(target, data);
        assertEq(result, success);
    }

    function test_RevertIfTheTransactionRevertsIfLockerNotEqualsGateway(address target, bytes memory data) external {
        // it revert if the transaction reverts if locker not equals gateway

        address accountantMocked = address(new MockAccountant());
        address gateway = address(new MockModuleManager());
        vm.label({account: gateway, newLabel: "Mocked Gateway"});

        vm.assume(address(locker) != address(0));
        vm.assume(address(locker) != gateway);
        vm.label({account: address(locker), newLabel: "Locker"});

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        ProtocolContextHarness protocolContextHarness =
            new ProtocolContextHarness(protocolId, protocolController, address(locker), gateway);

        vm.mockCallRevert(
            gateway,
            abi.encodeWithSelector(
                IModuleManager.execTransactionFromModule.selector,
                locker,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                IModuleManager.Operation.Call
            ),
            "UNEXPECTED_REVERT"
        );
        vm.expectRevert("UNEXPECTED_REVERT");
        protocolContextHarness._expose_executeTransaction(target, data);
    }
}
