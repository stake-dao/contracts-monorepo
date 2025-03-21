// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";
import {ProtocolContextHarness} from "test/unit/ProtocolContext/ProtocolContextHarness.t.sol";
import "./Base.t.sol";

/// @title ProtocolContextBaseTest
/// @notice Base test contract specifically for ProtocolContext tests
abstract contract ProtocolContextBaseTest is BaseTest {
    address internal protocolController;
    address internal accountant;
    address internal protocolContext;
    address internal protocolContextHarness;

    function setUp() public virtual override {
        super.setUp();

        protocolController = address(new MockRegistry());
        accountant = address(new MockAccountant());
    }

    function _replaceProtocolContextWithProtocolContextHarness(address customProtocolContext) internal {
        _deployHarnessCode(
            "out/ProtocolContextHarness.t.sol/ProtocolContextHarness.json",
            abi.encode(protocolId, protocolController, locker, gateway),
            customProtocolContext
        );
        protocolContextHarness = address(ProtocolContextHarness(customProtocolContext));
    }

    modifier _cheat_replaceProtocolContextWithProtocolContextHarness() {
        _replaceProtocolContextWithProtocolContextHarness(address(protocolContext));
        vm.label({account: address(protocolContext), newLabel: "ProtocolContextHarness"});

        _;
    }

    function deployProtocolContext() internal returns (ProtocolContext context) {
        address accountantMocked = address(new MockAccountant());
        address gatewayMocked = address(new MockModuleManager());

        vm.mockCall(
            protocolController,
            abi.encodeWithSelector(IProtocolController.accountant.selector, protocolId),
            abi.encode(accountantMocked)
        );

        vm.mockCall(
            accountantMocked, abi.encodeWithSelector(IAccountant.REWARD_TOKEN.selector), abi.encode(makeAddr("token"))
        );

        return new ProtocolContext(protocolId, protocolController, makeAddr("locker"), gatewayMocked);
    }
}

contract MockAccountant {
    function REWARD_TOKEN() external view returns (address) {}
}

contract MockModuleManager {
    function execTransactionFromModule(address to, uint256 value, bytes memory data, IModuleManager.Operation operation)
        external
        returns (bool success)
    {}
}
