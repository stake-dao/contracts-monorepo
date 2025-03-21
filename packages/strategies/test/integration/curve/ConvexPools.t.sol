// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "test/integration/curve/CurveFactory.t.sol";
import "test/integration/curve/CurveIntegration.t.sol";

// @notice Selected Convex pool PIDs sorted by PID (highest to lowest)
// @dev Each integration test requires two PIDs to test multi-gauge functionality
// @dev Make sure both gauges are properly initialized with _setupGauge in setUp

uint256 constant CONVEX_POOL_437_PID = 437;

uint256 constant CONVEX_POOL_436_PID = 436;

uint256 constant CONVEX_POOL_435_PID = 435;

uint256 constant CONVEX_POOL_434_PID = 434;

uint256 constant CONVEX_POOL_433_PID = 433;

uint256 constant CONVEX_POOL_432_PID = 432;

uint256 constant CONVEX_POOL_431_PID = 431;

uint256 constant CONVEX_POOL_430_PID = 430;

contract CONVEX_POOL_437_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_437_PID) {}

// Integration test using 437 and 436
contract CONVEX_POOL_437_PID_Integration_Test is CurveIntegrationTest(CONVEX_POOL_437_PID, CONVEX_POOL_436_PID) {}

contract CONVEX_POOL_436_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_436_PID) {}

contract CONVEX_POOL_435_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_435_PID) {}

// Integration test using 435 and 434
contract CONVEX_POOL_435_PID_Integration_Test is CurveIntegrationTest(CONVEX_POOL_435_PID, CONVEX_POOL_434_PID) {}

contract CONVEX_POOL_434_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_434_PID) {}

contract CONVEX_POOL_433_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_433_PID) {}

// Integration test using 433 and 432
contract CONVEX_POOL_433_PID_Integration_Test is CurveIntegrationTest(CONVEX_POOL_433_PID, CONVEX_POOL_432_PID) {}

contract CONVEX_POOL_432_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_432_PID) {}

contract CONVEX_POOL_431_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_431_PID) {}

// Integration test using 431 and 430
contract CONVEX_POOL_431_PID_Integration_Test is CurveIntegrationTest(CONVEX_POOL_431_PID, CONVEX_POOL_430_PID) {}

contract CONVEX_POOL_430_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_430_PID) {}
