// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "test/integration/curve/CurveFactory.t.sol";

// @notice All generations of liquidity gauge implementations.

uint256 constant BASE_LIQUIDITY_GAUGE_PID = 10;
/// First version of the liquidity gauge with no extra rewards support.

contract _BASE_LIQUIDITY_GAUGE_Test is CurveFactoryTest(BASE_LIQUIDITY_GAUGE_PID) {}

uint256 constant V2_LIQUIDITY_GAUGE_PID = 60;
/// Second version of the liquidity gauge with extra rewards support.

contract _V2_LIQUIDITY_GAUGE_Test is CurveFactoryTest(V2_LIQUIDITY_GAUGE_PID) {}

uint256 constant V5_LIQUIDITY_GAUGE_PID = 100;
/// Fifth version of the liquidity gauge with extra rewards support.

contract _V5_LIQUIDITY_GAUGE_Test is CurveFactoryTest(V5_LIQUIDITY_GAUGE_PID) {}

uint256 constant V6_LIQUIDITY_GAUGE_PID = 400;
/// Sixth version of the liquidity gauge with extra rewards support.

contract _V6_LIQUIDITY_GAUGE_Test is CurveFactoryTest(V6_LIQUIDITY_GAUGE_PID) {}
