// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {CurveVoter} from "src/voters/CurveVoter.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

contract DeployCurveVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        vm.startBroadcast();

        // 1. Deploy the CurveVoter contract
        CurveVoter curveVoter = new CurveVoter(gateway);

        // 2. Transfer the governance to the DAO
        curveVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
