// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "../../src/GovCurveVoter.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

contract Deploy is Script {
    address public constant DEPLOYER = address(DAO.MAIN_DEPLOYER);
    address public constant SAFE_PROPOSER = address(0x9ba4bD7B72B3a3966EFff094e2C955448f7FA5A7);
    address public constant GOVERNANCE = address(DAO.GOVERNANCE);

    GovCurveVoter govCurveVoter;

    function run() public {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(DEPLOYER);

        govCurveVoter = new GovCurveVoter();

        // Allow our safe proposer
        govCurveVoter.allowAddress(SAFE_PROPOSER);

        // Transfer governance to our Safe, our deployer will not be allowed anymore
        govCurveVoter.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
