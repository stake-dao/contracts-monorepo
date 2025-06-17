// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {DeployAndSetDepositModule} from "script/Router/03_DeployAndSetDepositModule.s.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleDeposit} from "src/router/RouterModuleDeposit.sol";

contract Router__SetupRouterDepositModuleScript is Test, DeployAndSetDepositModule {
    function test_RouterDepositModuleIsCorrectlyDeployed(bytes32 salt) external {
        Router router = new Router{salt: salt}();

        _run(address(router));

        assertEq(router.getModuleName(RouterIdentifierMapping.DEPOSIT), type(RouterModuleDeposit).name);
    }
}
