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

library CurveLocker {
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
}


library CurveStrategy {
    address internal constant ACCOUNTANT = 0x93b4B9bd266fFA8AF68e39EDFa8cFe2A62011Ce0;
    address internal constant PROTOCOL_CONTROLLER = 0x2d8BcE1FaE00a959354aCD9eBf9174337A64d4fb;
    address internal constant GATEWAY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    address internal constant STRATEGY = 0x021C3A83333a51d3c956F5c9748C384c897C8E14;

    address internal constant CONVEX_SIDECAR_IMPLEMENTATION = 0x735A969463967578Fcc17cEB9bba32893d00f71d;
    address internal constant CONVEX_SIDECAR_FACTORY = 0xf368a89e1731b9362670786d36866910c5334477;

    address internal constant FACTORY = 0x83922F1188Bd7661921b1FC02616F65B1DfA2092;
    address internal constant ALLOCATOR = 0x6Dbf307916Ae9c47549AbaF11Cb476252a14Ee9D;

    address internal constant REWARD_VAULT_IMPLEMENTATION = 0x74D8dd40118B13B210D0a1639141cE4458CAe0c0;
    address internal constant REWARD_RECEIVER_IMPLEMENTATION = 0x8E57D90Ef325F2BeDf86333be784b4499f8829df;
}