// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.sol";

/// @title CurveL2Integration - L2 Curve Integration Test
/// @notice Integration test for Curve protocol on L2 with Convex.
abstract contract CurveL2Integration is BaseIntegrationTest {
    /// @notice The configuration for the test.
    struct Config {
        string chain;
        bytes4 protocolId;
        uint256 blockNumber;
        address rewardToken;
        address minter;
        address locker;
        bool harvestPolicy;
        bool isOnlyBoost;
    }

    /// @notice The configuration for the test.
    Config public config;

    /// @notice The Curve Strategy contract.
    CurveStrategy public curveStrategy;

    constructor(Config memory _config) {
        config = _config;
    }

    function setUp() public virtual override {
        vm.createSelectFork(config.chain, config.blockNumber);

        /// 1. Setup protocol
        _beforeSetup({
            _rewardToken: config.rewardToken,
            _locker: config.locker,
            _protocolId: config.protocolId,
            _harvestPolicy: config.harvestPolicy
        });

        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            new CurveStrategy({
                _registry: address(protocolController),
                _locker: config.locker,
                _gateway: address(gateway),
                _minter: config.minter
            })
        );
    }

    function _initializeProtocol() internal override {}

    function _performCommonSetup() internal override {}
}
