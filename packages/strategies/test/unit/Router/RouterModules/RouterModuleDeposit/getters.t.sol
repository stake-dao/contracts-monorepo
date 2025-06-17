// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleDeposit} from "src/router/RouterModuleDeposit.sol";

contract RouterModuleDeposit__getters is Test {
    RouterModuleDeposit internal module;

    function setUp() public {
        module = new RouterModuleDeposit();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleDeposit).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
