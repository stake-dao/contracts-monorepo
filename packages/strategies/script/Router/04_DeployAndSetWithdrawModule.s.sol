// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {Router} from "src/Router.sol";
import {RouterIdentifierMapping} from "src/router/RouterIdentifierMapping.sol";
import {RouterModuleWithdraw} from "src/router/RouterModuleWithdraw.sol";

contract DeployAndSetWithdrawModule is Script {
    function _run(address router) internal {
        Router(router).setModule(RouterIdentifierMapping.WITHDRAW, address(new RouterModuleWithdraw()));
    }

    /// @notice Deploy the RouterModuleWithdraw contract and set it in the Router
    /// @dev The `ROUTER` (address) environment variable must be set
    function run() external {
        vm.startBroadcast();

        address router = vm.envAddress("ROUTER");
        _run(router);

        vm.stopBroadcast();
    }
}
