// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";


import {PendleVaultFactory} from "src/pendle/PendleVaultFactory.sol";

interface PendleStrategy {
    function setVaultGaugeFactory(address _vaultGaugeFactory) external;
    function vaultGaugeFactory() external returns (address);
}

contract DeployYearnStrategy is Script, Test {
    PendleVaultFactory public factory;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        factory = new PendleVaultFactory(PENDLE.STRATEGY, DAO.STRATEGY_SDT_DISTRIBUTOR);

        PendleStrategy(PENDLE.STRATEGY).setVaultGaugeFactory(address(factory));

        // Check values 
        if(factory.strategy() != PENDLE.STRATEGY) {
            revert("NOPE");
        }

        if(factory.sdtDistributor() != DAO.STRATEGY_SDT_DISTRIBUTOR) {
            revert("NOPE");
        }

        if(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory() != address(factory)) {
            revert("NOPE");
        }

        vm.stopBroadcast();
    }
}
