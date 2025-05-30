// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {IVoter} from "src/interfaces/IVoter.sol";
import {VoterPermissionManager} from "src/VoterPermissionManager.sol";

contract SetPermissionGauges is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        IVoter voter = IVoter(vm.envAddress("VOTER_ADDRESS"));

        // Check if the voter is deployed
        require(address(voter).code.length > 0, "Voter not deployed");

        // 1. Deploy the PendleVoter contract
        vm.startBroadcast();
        voter.setPermission(msg.sender, VoterPermissionManager.Permission.GAUGES_ONLY);
        vm.stopBroadcast();
    }
}
