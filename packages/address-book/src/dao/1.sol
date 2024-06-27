// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.6.0;

library DAO {
    /// Token addresses and revenue sharing.
    address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address public constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;
    address public constant VESDT_BOOST_PROXY = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;
    address public constant VEBOOST = 0x47B3262C96BB55A8D2E4F8E3Fed29D2eAB6dB6e9;
    address public constant FEE_DISTRIBUTOR = 0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92;
    address public constant PROXY_ADMIN = 0xfE612c237A81527a86f2Cac1FD19939CF4F91B9B;
    address public constant SMART_WALLET_CHECKER = 0x37E8386602d9EBEa2c56dd11d8E142290595f1b5;

    /// Recipient
    address public constant TREASURY = 0x9EBBb3d59d53D6aD3FA5464f36c2E84aBb7cf5c1;
    address public constant VESDT_FEES_RECIPIENT = 0x1fE537BD59A221854a53a5B7a81585B572787fce;
    address public constant LIQUIDITY_FEES_RECIPIENT = 0x576D7AD8eAE92D9A972104Aac56c15255dDBE080;

    /// SDT Distribution.
    address public constant LOCKER_SDT_DISTRIBUTOR = 0x8Dc551B4f5203b51b5366578F42060666D42AB5E;
    address public constant STRATEGY_SDT_DISTRIBUTOR = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

    address public constant LOCKER_GAUGE_CONTROLLER = 0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882;
    address public constant STRATEGY_GAUGE_CONTROLLER = 0x3F3F0776D411eb97Cfa4E3eb25F33c01ca4e7Ca8;

    /// veSDT on-chain voting addreses.
    address public constant AGENT_APP = 0x30f9fFF0f55d21D666E28E650d0Eb989cA44e339;
    address public constant VOTING_APP = 0x82e631fe565E06ea51a00fAbcd79645272f654eB;

    /// Common addresses.
    address public constant MAIN_DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    // Automation
    address public constant ALL_MIGHT = 0x0000000a3Fc396B89e4c11841B39D9dff85a5D05;
    address public constant BOTMARKET = 0xADfBFd06633eB92fc9b58b3152Fe92B0A24eB1FF;
}
