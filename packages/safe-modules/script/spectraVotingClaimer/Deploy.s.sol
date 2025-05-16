// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "../../src/SpectraVotingClaimer.sol";
import {DAO} from "address-book/src/DAOBase.sol";

contract Deploy is Script {
    address public constant MERKLE = address(0x665d334388012d17F1d197dE72b7b708ffCCB67d);
    // not all might
    address public constant ALL_MIGHT = address(0x90569D8A1cF801709577B24dA526118f0C83Fc75);

    SpectraVotingClaimer spectraVotingClaimer;

    function run() public {
        vm.createSelectFork("base");
        vm.startBroadcast();

        spectraVotingClaimer = new SpectraVotingClaimer(MERKLE);

        // Allow our safe proposer
        spectraVotingClaimer.allowAddress(ALL_MIGHT);

        // Transfer governance to our Safe, our deployer will not be allowed anymore
        spectraVotingClaimer.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
