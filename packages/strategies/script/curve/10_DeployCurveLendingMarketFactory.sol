// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {DAO} from "@address-book/src/DaoEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";

contract DeployCurveLendingMarketFactoryScript is Script {
    function run() external returns (CurveLendingMarketFactory curveLendingMarketFactory) {
        address protocolController = vm.envAddress("PROTOCOL_CONTROLLER");
        address governance = vm.envOr("OVERRIDE_GOVERNANCE", DAO.GOVERNANCE);

        require(protocolController.code.length > 0, "ProtocolController not deployed");
        require(governance != address(0), "Invalid governance address");

        vm.startBroadcast();

        curveLendingMarketFactory = new CurveLendingMarketFactory(protocolController, CurveProtocol.META_REGISTRY);
        curveLendingMarketFactory.transferOwnership(governance);

        vm.stopBroadcast();

        console.log("--> Don't forge to accept the governance with: %s", governance);
    }
}
