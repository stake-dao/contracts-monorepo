// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {CommonUniversal} from "./CommonUniversal.sol";

library Common {
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;

    // DEPLOYER
    address internal constant CREATE2_FACTORY = CommonUniversal.CREATE2_FACTORY;
    address internal constant CREATE3_FACTORY = CommonUniversal.CREATE3_FACTORY;

    // SAFE
    address internal constant SAFE_PROXY_FACTORY = CommonUniversal.SAFE_PROXY_FACTORY;
    address internal constant SAFE_SINGLETON = CommonUniversal.SAFE_SINGLETON;
    address internal constant SAFE_FALLBACK_HANDLER = CommonUniversal.SAFE_FALLBACK_HANDLER;
}
