// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {Router} from "src/Router.sol";

contract DeployRouter is Script {
    function _run() internal returns (Router router) {
        router = new Router();
        router.transferOwnership(DAO.GOVERNANCE);
    }

    /// @notice Deploy the Router contract and transfer ownership to the DAO
    /// @return router The address of the deployed Router contract
    function run() external returns (Router router) {
        vm.startBroadcast();

        router = _run();

        vm.stopBroadcast();
    }
}
