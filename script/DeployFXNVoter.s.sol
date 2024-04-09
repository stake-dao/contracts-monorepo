// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "src/fx/voter/FXNVoter.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";

contract DeployFXNVoter is Script {
    FXNVoter internal voter;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        voter = new FXNVoter(Fx.GAUGE_CONTROLLER, FXN.LOCKER, DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
