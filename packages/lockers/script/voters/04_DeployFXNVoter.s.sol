// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {FXNVoter} from "src/voters/FXNVoter.sol";
import {VoterPermissionManager} from "src/voters/utils/VoterPermissionManager.sol";

contract DeployFXNVoter is Script {
    function run() public {
        // @dev: Mandatory env variable that specify the address of the gateway contract
        address gateway = vm.envAddress("GATEWAY");

        // @dev: Optional env variable that specify the addresses to authorize
        address[] memory addressToAuthorize = vm.envOr("AUTHORIZE_ADDRESSES", ",", new address[](0));

        vm.startBroadcast();

        // 1. Deploy the FXNVoter contract
        FXNVoter fxnVoter = new FXNVoter(gateway);

        // 2. Authorize the provided addresses to vote on gauges
        for (uint256 i; i < addressToAuthorize.length; i++) {
            fxnVoter.setPermission(addressToAuthorize[i], VoterPermissionManager.Permission.ALL);
        }

        // 3. Transfer the governance to the DAO
        fxnVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
