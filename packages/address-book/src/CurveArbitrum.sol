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