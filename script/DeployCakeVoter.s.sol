// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {Pancake} from "address-book/protocols/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {CakeVoter} from "src/cake/voter/CakeVoter.sol";

contract DeployCakeVoter is Script {
    CakeVoter internal voter;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        voter = new CakeVoter(Pancake.GAUGE_CONTROLLER, CAKE.LOCKER, CAKE.EXECUTOR, DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}