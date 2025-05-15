// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library FXNProtocol {
    address internal constant FXN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;
    address internal constant VEFXN = 0xEC6B8A3F3605B083F7044C0F31f2cac0caf1d469;

    address internal constant FEE_DISTRIBUTOR = 0x851AAEA3A2757D457E1Ce88C3808C1690213e432;
    address internal constant GAUGE_CONTROLLER = 0xe60eB8098B34eD775ac44B1ddE864e098C6d7f37;
    address internal constant SMART_WALLET_CHECKER = 0xD71B8B76015F296E53D41e8288a8a13eAfFff2ea;
}

library FXNLocker {
    address internal constant TOKEN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;
    address internal constant SDTOKEN = 0xe19d1c837B8A1C83A56cD9165b2c0256D39653aD;
    address internal constant LOCKER = 0x75736518075a01034fa72D675D36a47e9B06B2Fb;
    address internal constant DEPOSITOR = 0x7995192bE61EA0B28ce14183DDA51eDF78F1c7AB;
    address internal constant GAUGE = 0xbcfE5c47129253C6B8a9A00565B3358b488D42E0;

    address internal constant ACCUMULATOR = 0x23ab5100acaFF53d00ad92BB8Df75a72e7a3Bc4a;
    address internal constant VOTER = 0x5181291355Abe5F3f1812a0aA888A73B9A16c91F;
}

library FXNVotemarket {
    address internal constant PLATFORM = 0x00000007D987c2Ea2e02B48be44EC8F92B8B06e8;
}
