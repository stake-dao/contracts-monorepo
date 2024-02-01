// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DAO} from "address-book/dao/1.sol";
import {AngleVoterV5} from "src/angle/voter/AngleVoterV5.sol";

contract DeployAngleVoterV5 is Script {

    AngleVoterV5 internal voter;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        voter = new AngleVoterV5();

        vm.stopBroadcast();
    }
}