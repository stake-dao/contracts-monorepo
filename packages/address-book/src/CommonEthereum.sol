// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {CommonUniversal} from "./CommonUniversal.sol";

library Common {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
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

    // Morpho
    address internal constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address internal constant MORPHO_CHAINLINK_ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address internal constant MORPHO_META_MORPHO_FACTORY = 0x1897A8997241C1cD4bD0698647e4EB7213535c24;

    // Chainlink
    address internal constant CHAINLINK_USDC_USD_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant CHAINLINK_USDT_USD_PRICE_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address internal constant CHAINLINK_CRVUSD_USD_PRICE_FEED = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;
    address internal constant CHAINLINK_ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_CRV_USD_PRICE_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
}
