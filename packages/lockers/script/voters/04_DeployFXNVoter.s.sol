// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {FXNVoter} from "src/voters/FXNVoter.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

contract DeployFXNVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        vm.startBroadcast();

        // 1. Deploy the FXNVoter contract
        FXNVoter fxnVoter = new FXNVoter(gateway);

        // 2. Transfer the governance to the DAO
        fxnVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
