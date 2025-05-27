// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {FraxVoter} from "src/voters/FraxVoter.sol";
import {VoterPermissionManager} from "src/voters/utils/VoterPermissionManager.sol";

contract DeployFraxVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        // @dev: Optional env variable that specify the addresses to authorize
        address[] memory addressToAuthorize = vm.envOr("AUTHORIZE_ADDRESSES", ",", new address[](0));

        vm.startBroadcast();

        // 1. Deploy the FraxVoter contract
        FraxVoter fraxVoter = new FraxVoter(gateway);

        // 2. Authorize the provided addresses to vote on gauges
        for (uint256 i; i < addressToAuthorize.length; i++) {
            fraxVoter.setPermission(addressToAuthorize[i], VoterPermissionManager.Permission.ALL);
        }

        // 3. Transfer the governance to the DAO
        fraxVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
