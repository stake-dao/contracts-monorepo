// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "test/yearn/YearnStrategyTestBis.t.sol";

address constant YWETH_GAUGE = 0x5943F7090282Eb66575662EADf7C60a717a7cE4D;

contract _YWETH_Strategy is YearnStrategyTestBis(YWETH_GAUGE) {}

address constant YDAI_GAUGE = 0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9;

contract _YDAI_Strategy is YearnStrategyTestBis(YDAI_GAUGE) {}

address constant YUSDC_GAUGE = 0x622fA41799406B120f9a40dA843D358b7b2CFEE3;

contract _YUSDC_Strategy is YearnStrategyTestBis(YUSDC_GAUGE) {}
