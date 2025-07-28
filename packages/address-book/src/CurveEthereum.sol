// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant VECRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address internal constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant SD_VE_CRV = 0x478bBC744811eE8310B461514BDc29D03739084D;

    address internal constant FEE_DISTRIBUTOR = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;
    address internal constant GAUGE_CONTROLLER = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
    address internal constant SMART_WALLET_CHECKER = 0xca719728Ef172d0961768581fdF35CB116e0B7a4;
    address internal constant CURVE_REGISTRY = 0xc522A6606BBA746d7960404F22a3DB936B6F4F50;

    address internal constant VOTING_APP_OWNERSHIP = 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356;
    address internal constant VOTING_APP_PARAMETER = 0xBCfF8B0b9419b9A88c44546519b1e909cF330399;
    address internal constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address internal constant VE_BOOST = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;

    // Convex
    address internal constant CONVEX_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
    address internal constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant CONVEX_TOKEN = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX

    address internal constant META_REGISTRY = 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC;
}

library CurveLocker {
    address internal constant TOKEN = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant SDTOKEN = 0xD1b5651E55D4CeeD36251c61c50C889B36F6abB5;
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address internal constant DEPOSITOR = 0x88C88Aa6a9cedc2aff9b4cA6820292F39cc64026;
    address internal constant GAUGE = 0x7f50786A0b15723D741727882ee99a0BF34e3466;
    address internal constant ACCUMULATOR = 0x615959a1d3E2740054d7130028613ECfa988056f;
    address internal constant VOTER = 0x20b22019406Cf990F0569a6161cf30B8e6651dDa;

    address internal constant STRATEGY = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;
    address internal constant FACTORY = 0xDC9718E7704f10DB1aFaad737f8A04bcd14C20AA;
    address internal constant VE_BOOST_DELEGATION = 0xe1F9C8ebBC80A013cAf0940fdD1A8554d763b9cf;
}

library CurveVotemarket {
    address internal constant PLATFORM = 0x0000000895cB182E6f983eb4D8b4E0Aa0B31Ae4c;
}
