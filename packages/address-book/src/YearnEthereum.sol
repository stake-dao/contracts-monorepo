// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library YearnProtocol {
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    address internal constant VEYFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;

    address internal constant YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address internal constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
}

library YearnLocker {
    address internal constant TOKEN = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SDTOKEN = 0x97983236bE88107Cc8998733Ef73D8d969c52E37;
    address internal constant LOCKER = 0xF750162fD81F9a436d74d737EF6eE8FC08e98220;
    address internal constant DEPOSITOR = 0xe56d9776fbB287A2f8Ba3f11375F51A24D7e25DB;
    address internal constant GAUGE = 0x5AdF559f5D24aaCbE4FA3A3a4f44Fdc7431E6b52;
    address internal constant ACCUMULATOR = 0xc74c0E02cbca62045C3a0375D31dAA40e49eE75B;

    address internal constant STRATEGY = 0x1be150a35bb8233d092747eBFDc75FB357c35168;
    address internal constant FACTORY = 0x1EFb2C804166be34a6956159646CAE9D0063b7fF;
}

library YearnVotemarket {}
