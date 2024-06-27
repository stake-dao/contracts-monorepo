// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.6.0;

library Angle {
    address public constant ANGLE = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;
    address public constant SAN_USDC_EUR = 0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad;
    address public constant SAN_DAI_EUR = 0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450;
}

library Balancer {
    address public constant HELPER = 0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;
}

library Curve {
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant VECRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    address public constant FEE_DISTRIBUTOR = 0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc;
    address public constant GAUGE_CONTROLLER = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
    address public constant SMART_WALLET_CHECKER = 0xca719728Ef172d0961768581fdF35CB116e0B7a4;

    address public constant VOTING_APP = 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356;
}

library Frax {
    address public constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address public constant FPIS = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    address public constant VEFXS = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
    address public constant VEFPIS = 0x574C154C83432B0A45BA3ad2429C3fA242eD7359;

    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address public constant GAUGE_CONTROLLER = 0x44ade9AA409B0C29463fF7fcf07c9d3c939166ce;
    address public constant SMART_WALLET_CHECKER = 0x53c13BA8834a1567474b19822aAD85c6F90D9f9F;

    address public constant FRAX_YIELD_DISTRIBUTOR = 0xc6764e58b36e26b08Fd1d2AeD4538c02171fA872;
    address public constant FPIS_YIELD_DISTRIBUTOR = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6;

    address public constant FRAXTAL_BRIDGE = 0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2;
}

library Yearn {
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    address public constant VEYFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;

    address public constant YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
}

library Pendle {
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    address public constant VEPENDLE = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;

    address public constant FEE_DISTRIBUTOR = 0x8C237520a8E14D658170A633D96F8e80764433b9;
}

library Maverick {
    address public constant MAV = 0x7448c7456a97769F6cD04F1E83A4a23cCdC46aBD;
    address public constant VEMAV = 0x4949Ac21d5b2A0cCd303C20425eeb29DCcba66D8;
}

library Fx {
    address public constant FXN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;
    address public constant VEFXN = 0xEC6B8A3F3605B083F7044C0F31f2cac0caf1d469;

    address public constant FEE_DISTRIBUTOR = 0x851AAEA3A2757D457E1Ce88C3808C1690213e432;
    address public constant GAUGE_CONTROLLER = 0xe60eB8098B34eD775ac44B1ddE864e098C6d7f37;
    address public constant SMART_WALLET_CHECKER = 0xD71B8B76015F296E53D41e8288a8a13eAfFff2ea;
}
