// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {CommonUniversal} from "./CommonUniversal.sol";

library Common {
    address internal constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

    // DEPLOYER
    address internal constant CREATE2_FACTORY = CommonUniversal.CREATE2_FACTORY;
    address internal constant CREATE3_FACTORY = CommonUniversal.CREATE3_FACTORY;

    // SAFE
    address internal constant SAFE_PROXY_FACTORY = CommonUniversal.SAFE_PROXY_FACTORY;
    address internal constant SAFE_SINGLETON = CommonUniversal.SAFE_SINGLETON;
    address internal constant SAFE_FALLBACK_HANDLER = CommonUniversal.SAFE_FALLBACK_HANDLER;

    // LayerZero
    address internal constant LAYERZERO_ENDPOINT = CommonUniversal.LAYERZERO_ENDPOINT;
}
