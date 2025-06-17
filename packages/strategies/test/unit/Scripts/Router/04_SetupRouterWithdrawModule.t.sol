// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DeployAndSetWithdrawModule} from "script/Router/04_DeployAndSetWithdrawModule.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleWithdraw} from "src/router/RouterModuleWithdraw.sol";

contract Router__SetupRouterWithdrawModuleScript is Test, DeployAndSetWithdrawModule {
    function test_RouterWithdrawModuleIsCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(router.getModuleName(RouterIdentifierMapping.WITHDRAW), type(RouterModuleWithdraw).name);
    }
}
