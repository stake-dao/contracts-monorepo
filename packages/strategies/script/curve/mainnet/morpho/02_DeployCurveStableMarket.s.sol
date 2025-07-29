// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";
import {CurveMorphoMarketDeployer} from "script/curve/mainnet/morpho/CurveMorphoMarketDeployer.sol";

contract DeployCurveStableMarketScript is CurveMorphoMarketDeployer {
    function run() external override returns (bytes memory) {
        return _run(CurveLendingMarketFactory.OracleType.STABLESWAP);
    }
}
