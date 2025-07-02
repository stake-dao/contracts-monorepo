// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {SpectraVoter} from "src/integrations/spectra/SpectraVoter.sol";
import {SpectraLocker} from "@address-book/src/SpectraBase.sol";
import {VoterPermissionManager} from "src/VoterPermissionManager.sol";

/// @title DeploySpectraVoter
/// @notice This script is used to deploy the SpectraVoter contract
/// @dev - A custom gateway can be passed to the script by providing the `GATEWAY` env variable.
///        If not provided, the locker will be used as the gateway.
///      - A list of addresses can be passed to the script by providing the `AUTHORIZE_ADDRESSES` env variable.
///        If not provided, no addresses will be authorized.
///
///      How to run the script:
///      AUTHORIZE_ADDRESSES="0x8e7801bAC71E92993f6924e7D767D7dbC5fCE0AE,0x8e7801bAC71E92993f6924e7D767D7dbC5fCE0AE" \
///      GATEWAY=0x64FCC3A02eeEba05Ef701b7eed066c6ebD5d4E51 forge script DeploySpectraVoter --broadcast \
///      --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://127.0.0.1:8545
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract DeploySpectraVoter is Script {
    function run() external {
        // @dev: Optional env variable that specify the address of the gateway contract
        //       If not provided, the locker will be used as the gateway
        address gateway = vm.envOr("GATEWAY", SpectraLocker.LOCKER);

        // @dev: Optional env variable that specify the addresses to authorize
        address[] memory addressToAuthorize = vm.envOr("AUTHORIZE_ADDRESSES", ",", new address[](0));

        vm.startBroadcast();

        // 1. Deploy the CurveVoter contract
        SpectraVoter spectraVoter = new SpectraVoter(gateway);

        // 2. Authorize the provided addresses to vote on gauges
        for (uint256 i; i < addressToAuthorize.length; i++) {
            spectraVoter.setPermission(addressToAuthorize[i], VoterPermissionManager.Permission.ALL);
        }

        // 3. Transfer the governance to the DAO
        spectraVoter.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
