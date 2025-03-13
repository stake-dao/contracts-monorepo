// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/integration/curve/BaseCurveTest.t.sol";

// TODO: Temporary, for SETUP Test
address constant LP_TOKEN = 0xff467c6E827ebbEa64DA1ab0425021E6c89Fbe0d;
address constant GAUGE = 0x294280254e1c8BcF56F8618623Ec9235e8415633;

contract _Deposit is BaseCurveTest(LP_TOKEN, GAUGE) {}
