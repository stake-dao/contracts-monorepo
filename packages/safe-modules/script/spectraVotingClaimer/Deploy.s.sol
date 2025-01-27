// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "../../src/SpectraVotingClaimer.sol";

contract Deploy is Script {
    address public constant DEPLOYER = address(0x428419Ad92317B09FE00675F181ac09c87D16450);
    address public constant GOVERNANCE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);
    address public constant MERKLE = address(0x665d334388012d17F1d197dE72b7b708ffCCB67d);
    address public constant ALL_MIGHT = address(0x90569D8A1cF801709577B24dA526118f0C83Fc75);

    SpectraVotingClaimer spectraVotingClaimer;

    function run() public {
        vm.createSelectFork("base");
        vm.startBroadcast(DEPLOYER);

        spectraVotingClaimer = new SpectraVotingClaimer(MERKLE);

        // Allow our safe proposer
        spectraVotingClaimer.allowAddress(ALL_MIGHT);
        
        // Transfer governance to our Safe, our deployer will not be allowed anymore
        spectraVotingClaimer.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}

