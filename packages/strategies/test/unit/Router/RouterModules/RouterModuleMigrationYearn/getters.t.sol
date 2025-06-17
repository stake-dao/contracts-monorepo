// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleMigrationYearn} from "src/router/RouterModuleMigrationYearn.sol";

contract RouterModuleMigrationYearn__getters is Test {
    RouterModuleMigrationYearn internal module;

    function setUp() public {
        module = new RouterModuleMigrationYearn();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleMigrationYearn).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
