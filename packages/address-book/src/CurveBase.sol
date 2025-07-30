// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library CurveProtocol {
    address internal constant CRV = 0x8Ee73c484A26e0A5df2Ee2a4960B789967dd0415;
    /// The factory is also the Minter.
    address internal constant FACTORY = 0xe35A879E5EfB4F1Bb7F70dCF3250f2e19f096bd8;
    address internal constant VECRV = 0xeB896fB7D1AaE921d586B0E5a037496aFd3E2412;
}

library CurveLocker {
    address internal constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
}

library CurveStrategy {
    address internal constant ACCOUNTANT = 0x8f872cE018898ae7f218E5a3cE6Fe267206697F8;
    address internal constant PROTOCOL_CONTROLLER = 0x8D34Ee08482c65F0871ECc160e3C343a0deC728a;
    address internal constant GATEWAY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    address internal constant STRATEGY = 0xDeD96cC511d96BDa66f4ae65723db99Cd8798308;

    address internal constant CONVEX_SIDECAR_IMPLEMENTATION = 0x0000000000000000000000000000000000000000;
    address internal constant CONVEX_SIDECAR_FACTORY = 0x0000000000000000000000000000000000000000;

    address internal constant FACTORY = 0x3df990855C3CC206bB99a1528d54979A87c3Df61;
    address internal constant ALLOCATOR = 0x91B69A17685D49fca9eDa932EE58fae92D7228fD;

    address internal constant REWARD_VAULT_IMPLEMENTATION = 0x69C1cB8F5e031D4044a45Ed67abdB6bE051b2992;
    address internal constant REWARD_RECEIVER_IMPLEMENTATION = 0x64D27Cf5e981814b777cB0Ca9be4BaCb1AAa0aDd;
}