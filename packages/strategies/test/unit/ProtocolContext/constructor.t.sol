// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";
import {MockAccountant, ProtocolContextBaseTest} from "test/ProtocolContextBaseTest.t.sol";

contract ProtocolContext__constructor is ProtocolContextBaseTest {
    address internal accountantMocked;

    function setUp() public override {
        super.setUp();

        accountantMocked = address(new MockAccountant());
    }

    function test_RevertIfProtocolControllerIsZeroAddress() external {
        // it revert if protocolController is zero address

        vm.expectRevert(ProtocolContext.ZeroAddress.selector);
        new ProtocolContext(0x12121212, address(0), makeAddr("locker"), makeAddr("gateway"));
    }

    function test_RevertIfGatewayIsZeroAddress() external {
        // it revert if gateway is zero address

        vm.expectRevert(ProtocolContext.ZeroAddress.selector);
        new ProtocolContext(0x12121212, makeAddr("protocolController"), makeAddr("locker"), address(0));
    }

    function test_SetsGateway(address gateway) external {
        // it sets gateway

        vm.assume(gateway != address(0));

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked,
            abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector),
            abi.encode(makeAddr("rewardToken"))
        );

        ProtocolContext context = new ProtocolContext(protocolId, protocolController, makeAddr("locker"), gateway);
        assertEq(context.GATEWAY(), gateway);
    }

    function test_SetsProtocolId(bytes4 _protocolId) external {
        // it sets protocolId

        vm.assume(_protocolId != 0);

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, _protocolId),
            abi.encode(accountant)
        );

        vm.mockCall(
            accountant, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("rewardToken"))
        );

        ProtocolContext context =
            new ProtocolContext(_protocolId, protocolController, makeAddr("locker"), makeAddr("gateway"));
        assertEq(context.PROTOCOL_ID(), _protocolId);
    }

    function test_SetsTheAccountantStoredInTheProtocolController() external {
        // it sets accountant

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountant)
        );

        vm.mockCall(
            accountant, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("rewardToken"))
        );

        ProtocolContext context =
            new ProtocolContext(protocolId, protocolController, makeAddr("locker"), makeAddr("gateway"));
        assertEq(context.ACCOUNTANT(), accountant);
    }

    function test_SetsTheRewardTokenStoredInTheAccountant() external {
        // it sets rewardToken

        address token = makeAddr("rewardToken");

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountant)
        );

        vm.mockCall(accountant, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(token));

        ProtocolContext context =
            new ProtocolContext(protocolId, protocolController, makeAddr("locker"), makeAddr("gateway"));
        assertEq(context.REWARD_TOKEN(), token);
    }

    function test_SetsProtocolController() external {
        // it sets protocolController

        address token = makeAddr("rewardToken");

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(token));

        ProtocolContext context =
            new ProtocolContext(protocolId, protocolController, makeAddr("locker"), makeAddr("gateway"));
        assertEq(address(context.PROTOCOL_CONTROLLER()), protocolController);
    }

    function test_SetsLockerToItsOwnValueGivenNonZeroLocker() external {
        // it sets locker to its own value given non zero locker

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked,
            abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector),
            abi.encode(makeAddr("rewardToken"))
        );

        ProtocolContext context =
            new ProtocolContext(protocolId, protocolController, makeAddr("locker"), makeAddr("gateway"));
        assertEq(address(context.PROTOCOL_CONTROLLER()), protocolController);

        assertEq(context.LOCKER(), makeAddr("locker"));
    }

    function test_SetsLockerToGatewayGivenZeroLocker() external {
        // it sets locker to gateway given zero locker

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked,
            abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector),
            abi.encode(makeAddr("rewardToken"))
        );

        ProtocolContext context = new ProtocolContext(protocolId, protocolController, address(0), makeAddr("gateway"));
        assertEq(address(context.PROTOCOL_CONTROLLER()), protocolController);

        assertEq(context.LOCKER(), makeAddr("gateway"));
    }
}
