// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "test/cake/PancakeERC20PMStrategyTest.t.sol";

address constant DEFI_EDGE_LPTOKEN = 0x52b59E3eAdc7C4ce8d3533020ca0Cd770E4eAbC3;
address constant DEFI_EDGE_WRAPPER = 0xCaaEadE6AFf11F7c69E1bEE3948C7CC1B3f4BC2E;

contract DefiEdge_Strategy_Test is PancakeERC20PMStrategyTest(DEFI_EDGE_LPTOKEN, DEFI_EDGE_WRAPPER) {}

address constant ALPACA_LPTOKEN = 0xb08eE41e88A2820cd572B4f2DFc459549790F2D7;
address constant ALPACA_WRAPPER = 0x0c8F9C4b0dF31D9E091f0F1Fc8222cFf0F34C32e;

contract Alpaca_Strategy_Test is PancakeERC20PMStrategyTest(ALPACA_LPTOKEN, ALPACA_WRAPPER) {}

address constant V2_LPTOKEN = 0x4cBEa76B4A1c42C356B4c52B0314A98313fFE9df;
address constant V2_WRAPPER = 0x2F3caA7637D5E7270091156D399cD06a8633d1dd;

contract V2_Strategy_Test is PancakeERC20PMStrategyTest(V2_LPTOKEN, V2_WRAPPER) {}
