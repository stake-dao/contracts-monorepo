// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xabC000d88f23Bb45525E447528DBF656A9D55bf5;
    address internal constant VECRV = 0x4D1AF9911e4c19f64Be36c36EF39Fd026Bc9bb61;

    address internal constant CONVEX_TOKEN = 0xaAFcFD42c9954C6689ef1901e03db742520829c5;
    address internal constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant CONVEX_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
}

library CurveVotemarket {
    address internal constant PLATFORM = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;
}

library CurveStrategy {
    address internal constant ACCOUNTANT = 0x93b4B9bd266fFA8AF68e39EDFa8cFe2A62011Ce0;
    address internal constant PROTOCOL_CONTROLLER = 0x2d8BcE1FaE00a959354aCD9eBf9174337A64d4fb;
    address internal constant GATEWAY = 0xe5d6D047DF95c6627326465cB27B64A8b77A8b91;

    address internal constant STRATEGY = 0x021C3A83333a51d3c956F5c9748C384c897C8E14;

    address internal constant CONVEX_SIDECAR_IMPLEMENTATION = 0x735A969463967578Fcc17cEB9bba32893d00f71d;
    address internal constant CONVEX_SIDECAR_FACTORY = 0xf368a89e1731b9362670786d36866910c5334477;

    address internal constant FACTORY = 0x83922F1188Bd7661921b1FC02616F65B1DfA2092;
    address internal constant ALLOCATOR = 0x6Dbf307916Ae9c47549AbaF11Cb476252a14Ee9D;

    address internal constant REWARD_VAULT_IMPLEMENTATION = 0x74D8dd40118B13B210D0a1639141cE4458CAe0c0;
    address internal constant REWARD_RECEIVER_IMPLEMENTATION = 0x8E57D90Ef325F2BeDf86333be784b4499f8829df;
}