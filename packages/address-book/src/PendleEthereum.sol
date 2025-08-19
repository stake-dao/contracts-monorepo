// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library PendleProtocol {
    address internal constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    address internal constant VEPENDLE = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;
    address internal constant FEE_DISTRIBUTOR = 0x8C237520a8E14D658170A633D96F8e80764433b9;
    address internal constant GAUGE_CONTROLLER = 0x47D74516B33eD5D70ddE7119A40839f6Fcc24e57;
}

library PendleLocker {
    address internal constant TOKEN = 0x808507121B80c02388fAd14726482e061B8da827;
    address internal constant SDTOKEN = 0x5Ea630e00D6eE438d3deA1556A110359ACdc10A9;
    address internal constant ASDTOKEN = 0x606462126E4Bd5c4D153Fe09967e4C46C9c7FeCf;
    address internal constant ASDTOKEN_ADAPTER = 0x5a26b6b7Bf04e55a0Dc3512564Bade1F31252a9f;
    address internal constant SYASDTOKEN = 0xae08c57475cb850751aD161917Ea941E2552CDF8;
    address internal constant LOCKER = 0xD8fa8dC5aDeC503AcC5e026a98F32Ca5C1Fa289A;
    address internal constant DEPOSITOR = 0x7F5c485D24fB1832A14f122C8722ef15C158Acb5;
    address internal constant GAUGE = 0x50DC9aE51f78C593d4138263da7088A973b8184E;
    address internal constant ACCUMULATOR = 0x65682CB35C8DEa1d3027CD37F37a245356BC4526;

    address internal constant VOTING_CONTROLLER = 0x44087E105137a5095c008AaB6a6530182821F2F0;
    address internal constant VOTERS_REWARDS_RECIPIENT = 0xe42a462dbF54F281F95776e663D8c942dcf94f17;

    address internal constant STRATEGY = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;
    address internal constant FACTORY = 0x4C1CF444Bbbfd3eD6608659B61A1107aF01181e5;
}

library PendleVotemarket {}
