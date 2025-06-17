// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DeployAndSetMigrationStakeDaoModule} from "script/Router/06_DeployAndSetMigrationStakeDaoModule.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleMigrationStakeDAOV1} from "src/router/RouterModuleMigrationStakeDAOV1.sol";

contract Router__SetupRouterMigrationStakeDaoModuleScript is Test, DeployAndSetMigrationStakeDaoModule {
    function test_RouterMigrationStakeDaoModuleIsCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(
            router.getModuleName(RouterIdentifierMapping.MIGRATION_STAKE_DAO_V1),
            type(RouterModuleMigrationStakeDAOV1).name
        );
    }
}
