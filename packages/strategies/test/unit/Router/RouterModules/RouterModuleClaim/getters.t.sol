// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleClaim} from "src/RouterModules/RouterModuleClaim.sol";

contract RouterModuleClaim__getters is Test {
    RouterModuleClaim internal module;

    function setUp() public {
        module = new RouterModuleClaim();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleClaim).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
