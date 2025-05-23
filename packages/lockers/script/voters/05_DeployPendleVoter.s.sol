// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {PendleVoter} from "src/voters/PendleVoter.sol";

contract DeployPendleVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        vm.startBroadcast();

        // 1. Deploy the PendleVoter contract
        PendleVoter pendleVoter = new PendleVoter(gateway);

        // 2. Transfer the governance to the DAO
        pendleVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
