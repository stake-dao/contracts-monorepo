// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleMigrationCurve} from "src/router/RouterModuleMigrationCurve.sol";

contract RouterModuleMigrationCurve__getters is Test {
    RouterModuleMigrationCurve internal module;

    function setUp() public {
        module = new RouterModuleMigrationCurve();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleMigrationCurve).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
