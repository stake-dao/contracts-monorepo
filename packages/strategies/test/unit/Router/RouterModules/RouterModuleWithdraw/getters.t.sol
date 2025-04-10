// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleWithdraw} from "src/RouterModules/RouterModuleWithdraw.sol";

contract RouterModuleWithdraw__getters is Test {
    RouterModuleWithdraw internal module;

    function setUp() public {
        module = new RouterModuleWithdraw();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleWithdraw).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
