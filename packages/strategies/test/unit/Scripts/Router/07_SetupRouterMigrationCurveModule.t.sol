// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DeployAndSetMigrationCurveModule} from "script/Router/07_DeployAndSetMigrationCurveModule.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleMigrationCurve} from "src/router/RouterModuleMigrationCurve.sol";

contract Router__SetupRouterMigrationCurveModuleScript is Test, DeployAndSetMigrationCurveModule {
    function test_RouterMigrationCurveModuleIsCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(router.getModuleName(RouterIdentifierMapping.MIGRATION_CURVE), type(RouterModuleMigrationCurve).name);
    }
}
