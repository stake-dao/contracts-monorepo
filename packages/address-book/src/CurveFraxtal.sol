// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x331B9182088e2A7d6D3Fe4742AbA1fB231aEcc56;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xeF672bD94913CB6f1d2812a6e18c1fFdEd8eFf5c;
    address internal constant VECRV = 0xc73e8d8f7A68Fc9d67e989250484E57Ae03a5Da3;

    address internal constant CONVEX_TOKEN = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CONVEX_BOOSTER = 0xd3327cb05a8E0095A543D582b5B3Ce3e19270389;
    address internal constant CONVEX_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
}


library CurveStrategy {
    address internal constant ACCOUNTANT = 0xa7d6dd95A06d95b65edf32B94ED46996E151c06f;
    address internal constant PROTOCOL_CONTROLLER = 0x4D4c2C4777625e97be1985682fAE5A53f5C44A80;
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address internal constant GATEWAY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    address internal constant STRATEGY = 0x341190ee097fCE6C6f0f81575c9842d98627257d;

    address internal constant CONVEX_SIDECAR_IMPLEMENTATION = 0xcAf1eE88407EC0940e7bc4Fe5917ab5f2E91f8a3;
    address internal constant CONVEX_SIDECAR_FACTORY = 0xb8368DD16E0A29ba8936856887003Be9bF31d3A4;

    address internal constant FACTORY = 0xbBA6a1ab4D927fC978AD92073487173a3a27bCEB;
    address internal constant ALLOCATOR = 0x3018f7115212b27da28773A03578137D21039B3C;

    address internal constant REWARD_VAULT_IMPLEMENTATION = 0xB8B83008a2Aca8D5F5feeae2c3e764DE0290c286;
    address internal constant REWARD_RECEIVER_IMPLEMENTATION = 0x182137f70A3639A07EC385DeC750d60B70bb3fbE;
}