// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "../../src/GovCurveVoter.sol";

contract Deploy is Script {
    address public constant DEPLOYER = address(0x428419Ad92317B09FE00675F181ac09c87D16450);
    address public constant SAFE_PROPOSER = address(0x9ba4bD7B72B3a3966EFff094e2C955448f7FA5A7);
    address public constant GOVERNANCE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);

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
