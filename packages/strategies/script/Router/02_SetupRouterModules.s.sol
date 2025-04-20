// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/RouterModules/RouterIdentifierMapping.sol";
import {RouterModuleClaim} from "src/RouterModules/RouterModuleClaim.sol";
import {RouterModuleDeposit} from "src/RouterModules/RouterModuleDeposit.sol";
import {RouterModuleMigrationCurve} from "src/RouterModules/RouterModuleMigrationCurve.sol";
import {RouterModuleMigrationStakeDAOV1} from "src/RouterModules/RouterModuleMigrationStakeDAOV1.sol";
import {RouterModuleMigrationYearn} from "src/RouterModules/RouterModuleMigrationYearn.sol";
import {RouterModuleWithdraw} from "src/RouterModules/RouterModuleWithdraw.sol";

contract SetRouterModules is Script {
    function _run(address router) internal {
        Router(router).setModule(RouterIdentifierMapping.DEPOSIT, address(new RouterModuleDeposit()));
        Router(router).setModule(RouterIdentifierMapping.WITHDRAW, address(new RouterModuleWithdraw()));
        Router(router).setModule(RouterIdentifierMapping.CLAIM, address(new RouterModuleClaim()));
        Router(router).setModule(
            RouterIdentifierMapping.MIGRATION_STAKE_DAO_V1, address(new RouterModuleMigrationStakeDAOV1())
        );
        Router(router).setModule(RouterIdentifierMapping.MIGRATION_CURVE, address(new RouterModuleMigrationCurve()));
        Router(router).setModule(RouterIdentifierMapping.MIGRATION_YEARN, address(new RouterModuleMigrationYearn()));
    }

    function run() external {
        vm.startBroadcast();

        _run(vm.envAddress("ROUTER"));

        vm.stopBroadcast();
    }
}
