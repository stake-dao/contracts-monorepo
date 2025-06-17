// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {SetRouterModules} from "script/Router/02_SetupRouterModules.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleClaim} from "src/router/RouterModuleClaim.sol";
import {RouterModuleDeposit} from "src/router/RouterModuleDeposit.sol";
import {RouterModuleWithdraw} from "src/router/RouterModuleWithdraw.sol";

contract Router__DeployRouterModulesScript is Test, SetRouterModules {
    function test_RouterModulesAreCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(router.getModuleName(RouterIdentifierMapping.DEPOSIT), type(RouterModuleDeposit).name);
        assertEq(router.getModuleName(RouterIdentifierMapping.WITHDRAW), type(RouterModuleWithdraw).name);
        assertEq(router.getModuleName(RouterIdentifierMapping.CLAIM), type(RouterModuleClaim).name);
    }
}
