// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {GaugeVoteRouter} from "src/voters/utils/GaugeVoteRouter.sol";

contract DeployGaugeVoteRouter is Script {
    function run() public {
        vm.startBroadcast();

        // 1. Deploy the GaugeVoteRouter contract
        new GaugeVoteRouter(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
