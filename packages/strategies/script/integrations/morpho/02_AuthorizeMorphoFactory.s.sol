// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";

contract AuthorizeMorphoFactoryScript is Script {
    function run() external {
        address factory = vm.envAddress("MORPHO_MARKET_FACTORY");
        require(factory.code.length > 0, "MorphoMarketFactory not deployed");

        vm.startBroadcast();

        MorphoMarketFactory(factory).MORPHO_BLUE().setAuthorization(factory, true);

        vm.stopBroadcast();
    }
}
