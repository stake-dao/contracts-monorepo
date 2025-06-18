// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library DAO {
    /// Token addresses and revenue sharing.
    address internal constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;
    address internal constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;
    address internal constant VESDT_BOOST_PROXY = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;
    address internal constant VEBOOST = 0x47B3262C96BB55A8D2E4F8E3Fed29D2eAB6dB6e9;
    address internal constant FEE_DISTRIBUTOR = 0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92;
    address internal constant PROXY_ADMIN = 0xfE612c237A81527a86f2Cac1FD19939CF4F91B9B;
    address internal constant SMART_WALLET_CHECKER = 0x37E8386602d9EBEa2c56dd11d8E142290595f1b5;
    address internal constant TIMELOCK = 0xD3cFc4E65a73BB6C482383EB38f5C3E1d1411616;

    /// Recipient
    address internal constant TREASURY = 0x9EBBb3d59d53D6aD3FA5464f36c2E84aBb7cf5c1;
    address internal constant VESDT_FEES_RECIPIENT = 0x1fE537BD59A221854a53a5B7a81585B572787fce;
    address internal constant LIQUIDITY_FEES_RECIPIENT = 0x576D7AD8eAE92D9A972104Aac56c15255dDBE080;

    address internal constant FEE_RECEIVER = 0x60136fefE23D269aF41aB72DE483D186dC4318D6;

    /// SDT Distribution.
    address internal constant LOCKER_SDT_DISTRIBUTOR = 0x8Dc551B4f5203b51b5366578F42060666D42AB5E;
    address internal constant STRATEGY_SDT_DISTRIBUTOR = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

    address internal constant LOCKER_GAUGE_CONTROLLER = 0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882;
    address internal constant STRATEGY_GAUGE_CONTROLLER = 0x3F3F0776D411eb97Cfa4E3eb25F33c01ca4e7Ca8;

    /// veSDT on-chain voting addreses.
    address internal constant AGENT_APP = 0x30f9fFF0f55d21D666E28E650d0Eb989cA44e339;
    address internal constant VOTING_APP = 0x82e631fe565E06ea51a00fAbcd79645272f654eB;

    /// Common addresses.
    address internal constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant LAPOSTE = 0xF0000058000021003E4754dCA700C766DE7601C2;
    address internal constant L2_SAFE_TREASURY = 0x5DA07af8913A4EAf09E5F569c20138b658906c17;

    // Automation
    address internal constant ALL_MIGHT = 0x0000000a3Fc396B89e4c11841B39D9dff85a5D05;
    address internal constant BOTMARKET = 0xADfBFd06633eB92fc9b58b3152Fe92B0A24eB1FF;
}