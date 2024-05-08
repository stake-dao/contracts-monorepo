// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {CakeIFOFactory} from "src/cake/ifo/CakeIFOFactory.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";

contract DeployFXNAccumulator is Script {
    CakeIFOFactory private factory;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);
        // it needs to be runned on bnb network
        require(block.chainid == 56, "Wrong network");

        // set feeReceiver as governance at deploy time
        factory = new CakeIFOFactory(CAKE.LOCKER, CAKE.EXECUTOR, DAO.GOVERNANCE, DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
