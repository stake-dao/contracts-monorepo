// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RouterModuleMigrationStakeDAOV1} from "src/router/RouterModuleMigrationStakeDAOV1.sol";

contract RouterModuleMigrationStakeDAOV1__getters is Test {
    RouterModuleMigrationStakeDAOV1 internal module;

    function setUp() public {
        module = new RouterModuleMigrationStakeDAOV1();
    }

    function test_ReturnsTheName() external view {
        // it returns the name of the module
        assertEq(module.name(), type(RouterModuleMigrationStakeDAOV1).name);
    }

    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(module.version(), "1.0.0");
    }
}
