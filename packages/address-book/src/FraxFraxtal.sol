// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library FraxProtocol {
    address internal constant FXS = 0xFc00000000000000000000000000000000000002;
    address internal constant VEFXS = 0x007FD070a7E1B0fA1364044a373Ac1339bAD89CF;
    address internal constant YIELD_DISTRIBUTOR = 0x21359d1697e610e25C8229B2C57907378eD09A2E;
    address internal constant DELEGATION_REGISTRY = 0xF5cA906f05cafa944c27c6881bed3DFd3a785b6A;
    address internal constant FRAXTAL_BRIDGE = 0x4200000000000000000000000000000000000010;

    address internal constant FRAX = 0xFc00000000000000000000000000000000000001;
    address internal constant FPIS = 0xfc00000000000000000000000000000000000004;
}

library FraxLocker {}

library FraxVotemarket {}
