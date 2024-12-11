// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";
import "address-book/src/strategies/56.sol";

import "src/bnb/cake/FeeReceiver.sol";

import "src/common/fee/VeSDTRecipient.sol";
import "src/common/fee/TreasuryRecipient.sol";
import "src/common/fee/LiquidityFeeRecipient.sol";

import "src/bnb/cake/Voter.sol";
import {Pancake} from "address-book/src/protocols/56.sol";

contract Deploy is Script {
    CakeVoter public voter;

    address internal DEPLOYER = 0x8898502BA35AB64b3562aBC509Befb7Eb178D4df;

    function run() public {
        vm.createSelectFork("bnb");
        vm.startBroadcast(DEPLOYER);

        voter = new CakeVoter(
            Pancake.GAUGE_CONTROLLER,
            CAKE.LOCKER,
            CAKE.EXECUTOR,
            DAO.GOVERNANCE
        );

        require(voter.locker() == CAKE.LOCKER, "Nope");
        require(voter.gaugeController() == Pancake.GAUGE_CONTROLLER, "Nope");
        require(address(voter.executor()) == CAKE.EXECUTOR, "Nope");
        require(voter.governance() == DAO.GOVERNANCE, "Nope");

        vm.stopBroadcast();
    }
}
