// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {DAO} from "@address-book/src/DaoEthereum.sol";

contract DeployMorphoMarketFactoryScript is Script {
    function _run(address protocolController, address morphoBlue, address governance)
        internal
        returns (MorphoMarketFactory morphoMarketFactory)
    {
        vm.startBroadcast();

        morphoMarketFactory = new MorphoMarketFactory(morphoBlue, protocolController);
        morphoMarketFactory.transferOwnership(governance);

        vm.stopBroadcast();
    }

    function run() external returns (MorphoMarketFactory morphoMarketFactory) {
        address protocolController = vm.envAddress("PROTOCOL_CONTROLLER");
        address morphoBlue = vm.envOr("MORPHO_BLUE", Common.MORPHO_BLUE);
        address governance = vm.envOr("GOVERNANCE", DAO.GOVERNANCE);

        require(protocolController.code.length > 0, "ProtocolController not deployed");
        require(morphoBlue.code.length > 0, "MorphoBlue not deployed");
        require(governance != address(0), "Invalid governance address");

        vm.startBroadcast();

        morphoMarketFactory = new MorphoMarketFactory(morphoBlue, protocolController);
        morphoMarketFactory.transferOwnership(governance);

        vm.stopBroadcast();

        console.log("--> Don't forge to accept the governance with: %s", governance);
    }
}
