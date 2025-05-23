// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library FraxProtocol {
    address internal constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant FPIS = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    address internal constant VEFXS = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
    address internal constant VEFPIS = 0x574C154C83432B0A45BA3ad2429C3fA242eD7359;

    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address internal constant GAUGE_CONTROLLER = 0x44ade9AA409B0C29463fF7fcf07c9d3c939166ce;
    address internal constant SMART_WALLET_CHECKER = 0x53c13BA8834a1567474b19822aAD85c6F90D9f9F;

    address internal constant FRAX_YIELD_DISTRIBUTOR = 0xc6764e58b36e26b08Fd1d2AeD4538c02171fA872;
    address internal constant FPIS_YIELD_DISTRIBUTOR = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6;

    address internal constant FRAXTAL_BRIDGE = 0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2;
}

library FraxLocker {
    address internal constant TOKEN = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant SDTOKEN = 0x402F878BDd1f5C66FdAF0fabaBcF74741B68ac36;
    address internal constant LOCKER = 0xCd3a267DE09196C48bbB1d9e842D7D7645cE448f;
    address internal constant DEPOSITOR = 0xFaF3740167B866b571465B063c6B3A71Ba9b6285;
    address internal constant GAUGE = 0xF3C6e8fbB946260e8c2a55d48a5e01C82fD63106;
    address internal constant ACCUMULATOR = 0xAB8a21516465D9Fc57c621f57eCAB838c1910BD6;
    address internal constant VOTER = 0xaE26E4478FF6BbC555EAE020AFFea3B505fC4D05;

    address internal constant STRATEGY = 0xf285Dec3217E779353350443fC276c07D05917c3;
}

library FraxVotemarket {
    address internal constant PLATFORM = 0x000000060e56DEfD94110C1a9497579AD7F5b254;
}
