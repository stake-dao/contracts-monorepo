// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./Base.t.sol";

import {ProtocolContext} from "src/ProtocolContext.sol";
import {ProtocolContextHarness} from "test/unit/ProtocolContext/ProtocolContextHarness.t.sol";

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
}

contract MockAccountant {
    function REWARD_TOKEN() external view returns (address) {}
}
