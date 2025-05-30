// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {VoteGaugeRouter} from "src/VoteGaugeRouter.sol";

contract DeployGaugeVoteRouter is Script {
    function run() public {
        vm.startBroadcast();

        // 1. Deploy the VoteGaugeRouter contract
        new VoteGaugeRouter(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
