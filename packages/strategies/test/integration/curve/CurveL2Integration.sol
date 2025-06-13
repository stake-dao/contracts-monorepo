// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactory} from "src/integrations/curve/L2/CurveFactory.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {CurveStrategy} from "src/integrations/curve/L2/CurveStrategy.sol";
import {ConvexSidecar} from "src/integrations/curve/L2/ConvexSidecar.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/L2/ConvexSidecarFactory.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";

import "test/integration/BaseIntegrationTest.sol";

/// @title CurveIntegration - L2 Curve Integration Test
/// @notice Integration test for Curve protocol on L2 with Convex.
abstract contract CurveL2Integration is BaseIntegrationTest {
    /// @notice Base configuration for the test.
    struct BaseConfig {
        string chain;
        bytes4 protocolId;
        uint256 blockNumber;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address minter;
        address boostProvider;
        address oldStrategy;
        address gaugeController;
    }

    /// @notice Convex-specific configuration.
    struct ConvexConfig {
        bool isOnlyBoost;
        address cvx;
        address convexBoostHolder;
        address booster;
    }

    /// @notice Combined configuration for the test.
    struct Config {
        BaseConfig base;
        ConvexConfig convex;
    }

    /// @notice The configuration for the test.
    Config public config;

    constructor(Config memory _config) {
        config = _config;
    }

    function setUp()
        public
        virtual
        doSetup(
            config.base.chain,
            config.base.blockNumber,
            config.base.rewardToken,
            config.base.locker,
            config.base.protocolId,
            config.base.harvestPolicy
        )
    {
        /// 1. Get the gauges.
        gauges = getGauges();

        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            new CurveStrategy({
                _registry: address(protocolController),
                _locker: config.base.locker,
                _gateway: address(gateway)
            })
        );

        /// 3. Check if the strategy is only boost.
        if (config.convex.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                new ConvexSidecar({
                    _accountant: address(accountant),
                    _protocolController: address(protocolController),
                    _cvx: config.convex.cvx,
                    _booster: config.convex.booster
                })
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                new ConvexSidecarFactory({
                    _implementation: address(sidecarImplementation),
                    _protocolController: address(protocolController),
                    _booster: config.convex.booster
                })
            );

            /// 3c. Deploy the OnlyBoostAllocator contract.
            allocator = new OnlyBoostAllocator({
                _locker: config.base.locker,
                _gateway: address(gateway),
                _convexSidecarFactory: sidecarFactory,
                _boostProvider: config.base.boostProvider,
                _convexBoostHolder: config.convex.convexBoostHolder
            });
        }

        factory = address(
            new CurveFactory(
                address(protocolController),
                address(rewardVaultImplementation),
                address(rewardReceiverImplementation),
                config.base.locker,
                address(gateway),
                config.convex.booster,
                sidecarFactory
            )
        );

        _clearLockerBalances();
        _allowMint();
    }

    function _clearLockerBalances() internal {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 balance = ILiquidityGauge(gauges[i]).balanceOf(config.base.locker);
            if (balance == 0) continue;

            address lpToken = ILiquidityGauge(gauges[i]).lp_token();
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Withdraw from gauge
            bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balance);
            SafeLibrary.execOnLocker(payable(gateway), config.base.locker, gauges[i], data, signatures);

            // Transfer to burn address
            data = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            SafeLibrary.execOnLocker(payable(gateway), config.base.locker, lpToken, data, signatures);
        }
    }

    function _allowMint() internal {
        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));
        /// Build data
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", strategy);
        /// Execute transaction
        SafeLibrary.execOnLocker(payable(gateway), config.base.locker, config.base.minter, data, signatures);
    }
}
