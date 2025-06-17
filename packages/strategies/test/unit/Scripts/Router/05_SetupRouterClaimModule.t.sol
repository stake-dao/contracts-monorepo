// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DeployAndSetClaimModule} from "script/Router/05_DeployAndSetClaimModule.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleClaim} from "src/router/RouterModuleClaim.sol";

contract Router__SetupRouterClaimModuleScript is Test, DeployAndSetClaimModule {
    function test_RouterClaimModuleIsCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(router.getModuleName(RouterIdentifierMapping.CLAIM), type(RouterModuleClaim).name);
    }
}
