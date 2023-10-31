// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "test/yearn/YearnStrategyTestBis.t.sol";

address constant YETH_GAUGE = 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59;

contract _YETH_Strategy is YearnStrategyTestBis {}

address constant YFI_ETH_GAUGE = 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3;

contract _YFI_ETH_Strategy is YearnStrategyTestBis {}

address constant YCRV_GAUGE = 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C;

contract _YCRV_Strategy is YearnStrategyTestBis {}

address constant DYFI_ETH_GAUGE = 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc;

contract _DYFI_ETH_Strategy is YearnStrategyTestBis {}
