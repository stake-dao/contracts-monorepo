// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {BalancerVoter} from "src/voters/BalancerVoter.sol";

contract DeployBalancerVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        vm.startBroadcast();

        // 1. Deploy the BalancerVoter contract
        BalancerVoter balancerVoter = new BalancerVoter(gateway);

        // 2. Transfer the governance to the DAO
        balancerVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
