// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library PancakeswapProtocol {
    address internal constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address internal constant VECAKE = 0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB;
    address internal constant GAUGE_CONTROLLER = 0xbCfBf7ED1756FE478B071687cb430C7B3eB682f1;

    address internal constant REVENUE_SHARING_POOL_1 = 0x9cac9745731d1Cf2B483f257745A512f0938DD01;
    address internal constant REVENUE_SHARING_POOL_2 = 0xCaF4e48a4Cb930060D0c3409F40Ae7b34d2AbE2D;
    address internal constant REVENUE_SHARING_POOL_GATEWAY = 0x011f2a82846a4E9c62C2FC4Fd6fDbad19147D94A;
}

library PancakeswapLocker {
    address internal constant TOKEN = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address internal constant SDTOKEN = 0x6a1c1447F97B27dA23dC52802F5f1435b5aC821A;
    address internal constant LOCKER = 0x1E6F87A9ddF744aF31157d8DaA1e3025648d042d;
    address internal constant DEPOSITOR = 0x32ee46755AE81ce917392ed1fB21f74a8104515B;
    address internal constant GAUGE = 0xE2496134149e6CD3f3A577C2B08A6f54fC23e6e4;
    address internal constant ACCUMULATOR = 0xAA14AD0AD8B48406Baf2473692901e47430414F5;
    address internal constant EXECUTOR = 0x74B7639503bb632FfE86382af7C5a3121a41613a;
    address internal constant VOTER = 0x3c7b193aa39a85FDE911465d35CE3A74499F0A7B;

    address internal constant REDEEM = 0xD1Aa72713ccB1FE2983141EC176F1181F98E4908;
}

library PancakeswapVotemarket {
    address internal constant PLATFORM = 0x62c5D779f5e56F6BC7578066546527fEE590032c;
}
