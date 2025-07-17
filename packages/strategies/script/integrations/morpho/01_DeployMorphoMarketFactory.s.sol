// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";

contract DeployMorphoMarketFactoryScript is Script {
    function run() external returns (MorphoMarketFactory morphoMarketFactory) {
        address morphoBlue = vm.envOr("MORPHO_BLUE", Common.MORPHO_BLUE);
        require(morphoBlue.code.length > 0, "MorphoBlue not deployed");

        vm.startBroadcast();
        morphoMarketFactory = new MorphoMarketFactory(morphoBlue);
        vm.stopBroadcast();
    }
}
