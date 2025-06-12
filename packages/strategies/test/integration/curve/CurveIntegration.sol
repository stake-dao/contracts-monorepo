// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {IBooster} from "@interfaces/convex/IBooster.sol";

import "test/integration/BaseIntegrationTest.sol";

/// @title CurveIntegration - L2 Curve Integration Test
/// @notice Integration test for Curve protocol on L2 with Convex.
abstract contract CurveIntegration is BaseIntegrationTest {
    /// @notice The configuration for the test.
    struct Config {
        string chain;
        bytes4 protocolId;
        uint256 blockNumber;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address minter;
        address boostProvider;
        /// Only Boost Config
        bool isOnlyBoost;
        address cvx;
        address convexBoostHolder;
        address booster;
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
            config.chain,
            config.blockNumber,
            config.rewardToken,
            config.locker,
            config.protocolId,
            config.harvestPolicy
        )
    {
        /// 1. Get the gauges.
        gauges = getGauges();

        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            new CurveStrategy({
                _registry: address(protocolController),
                _locker: config.locker,
                _gateway: address(gateway),
                _minter: config.minter
            })
        );

        /// 3. Check if the strategy is only boost.
        if (config.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                new ConvexSidecar({
                    _accountant: address(accountant),
                    _protocolController: address(protocolController),
                    _cvx: config.cvx,
                    _booster: config.booster
                })
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                new ConvexSidecarFactory({
                    _implementation: address(sidecarImplementation),
                    _protocolController: address(protocolController),
                    _booster: config.booster
                })
            );

            /// 3c. Deploy the OnlyBoostAllocator contract.
            allocator = new OnlyBoostAllocator({
                _locker: config.locker,
                _gateway: address(gateway),
                _convexSidecarFactory: sidecarFactory,
                _boostProvider: config.boostProvider,
                _convexBoostHolder: config.convexBoostHolder
            });
        }

        factory = address(
            new CurveFactory({
                protocolController: address(protocolController),
                vaultImplementation: address(rewardVaultImplementation),
                rewardReceiverImplementation: address(rewardReceiverImplementation),
                locker: config.locker,
                gateway: address(gateway),
                convexSidecarFactory: sidecarFactory
            })
        );

        _clearLockerBalances();
        _allowMint();
    }

    function _clearLockerBalances() internal {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 balance = ILiquidityGauge(gauges[i]).balanceOf(config.locker);
            if (balance == 0) continue;

            address lpToken = ILiquidityGauge(gauges[i]).lp_token();
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Withdraw from gauge
            bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balance);
            SafeLibrary.execOnLocker(payable(gateway), config.locker, gauges[i], data, signatures);

            // Transfer to burn address
            data = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            SafeLibrary.execOnLocker(payable(gateway), config.locker, lpToken, data, signatures);
        }
    }

    function _allowMint() internal {
        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));
        /// Build data
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", strategy);
        /// Execute transaction
        SafeLibrary.execOnLocker(payable(gateway), config.locker, config.minter, data, signatures);
    }
}

contract CurveIntegrationTest is CurveIntegration {
    Config public _config = Config({
        chain: "mainnet",
        blockNumber: 22_316_395,
        rewardToken: CurveProtocol.CRV,
        locker: CurveLocker.LOCKER,
        protocolId: bytes4(keccak256("CURVE")),
        harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT,
        minter: CurveProtocol.MINTER,
        boostProvider: CurveProtocol.VE_BOOST,
        isOnlyBoost: true,
        cvx: CurveProtocol.CONVEX_TOKEN,
        convexBoostHolder: CurveProtocol.CONVEX_BOOSTER,
        booster: CurveProtocol.CONVEX_BOOSTER
    });

    // All pool IDs from the old tests
    uint256[] public poolIds = [68, 40, 437, 436, 435, 434, 433];

    constructor() CurveIntegration(_config) {}

    function getGauges() internal override returns (address[] memory) {
        // Get gauge addresses for all pool IDs
        IBooster booster = IBooster(CurveProtocol.CONVEX_BOOSTER);
        address[] memory gauges = new address[](poolIds.length);

        for (uint256 i = 0; i < poolIds.length; i++) {
            (,, address gauge,,,) = booster.poolInfo(poolIds[i]);

            // Mark as shutdown in old strategy
            vm.mockCall(
                CurveLocker.STRATEGY,
                abi.encodeWithSelector(bytes4(keccak256("isShutdown(address)")), gauge),
                abi.encode(true)
            );

            // Mock reward distributor as zero
            vm.mockCall(
                CurveLocker.STRATEGY,
                abi.encodeWithSelector(bytes4(keccak256("rewardDistributors(address)")), gauge),
                abi.encode(address(0))
            );

            gauges[i] = gauge;
        }

        return gauges;
    }

    function simulateRewards(RewardVault vault, uint256 amount) internal override {
        address gauge = vault.gauge();

        // Get the current integrate_fraction (might be mocked from previous calls)
        uint256 currentIntegrateFraction;
        try ILiquidityGauge(gauge).integrate_fraction(config.locker) returns (uint256 fraction) {
            currentIntegrateFraction = fraction;
        } catch {
            // Fallback if mocked and reverts
            currentIntegrateFraction = IMinter(config.minter).minted(config.locker, gauge);
        }

        // Add the new amount to existing state (incremental)
        uint256 newIntegrateFraction = currentIntegrateFraction + amount;

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, config.locker),
            abi.encode(newIntegrateFraction)
        );
    }
}
