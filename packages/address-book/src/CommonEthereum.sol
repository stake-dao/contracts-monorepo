// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {CommonUniversal} from "./CommonUniversal.sol";

library Common {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // DEPLOYER
    address internal constant CREATE2_FACTORY = CommonUniversal.CREATE2_FACTORY;
    address internal constant CREATE3_FACTORY = CommonUniversal.CREATE3_FACTORY;

    // SAFE
    address internal constant SAFE_PROXY_FACTORY = CommonUniversal.SAFE_PROXY_FACTORY;
    address internal constant SAFE_SINGLETON = CommonUniversal.SAFE_SINGLETON;
    address internal constant SAFE_L2_SINGLETON = CommonUniversal.SAFE_L2_SINGLETON;
    address internal constant SAFE_FALLBACK_HANDLER = CommonUniversal.SAFE_FALLBACK_HANDLER;

    // LayerZero
    address internal constant LAYERZERO_ENDPOINT = CommonUniversal.LAYERZERO_ENDPOINT;
}
