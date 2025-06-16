// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveIntegration.sol";
import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";

contract CurveMainnetIntegrationTest is CurveIntegration {
    Config public _config = Config({
        base: BaseConfig({
            chain: "mainnet",
            blockNumber: 22_316_395,
            rewardToken: CurveProtocol.CRV,
            locker: CurveLocker.LOCKER,
            protocolId: bytes4(keccak256("CURVE")),
            harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT,
            minter: CurveProtocol.MINTER,
            boostProvider: CurveProtocol.VE_BOOST,
            gaugeController: CurveProtocol.GAUGE_CONTROLLER,
            oldStrategy: CurveLocker.STRATEGY
        }),
        convex: ConvexConfig({
            isOnlyBoost: true,
            cvx: CurveProtocol.CONVEX_TOKEN,
            convexBoostHolder: CurveProtocol.CONVEX_BOOSTER,
            booster: CurveProtocol.CONVEX_BOOSTER
        })
    });

    // All pool IDs from the old tests
    uint256[] public poolIds = [68, 40, 437, 436, 435, 434, 433];

    constructor() CurveIntegration(_config) {}

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);

        for (uint256 i = 0; i < poolIds.length; i++) {
            uint256 poolId = poolIds[i];

            /// Deploy the vault and receiver.
            (address vault, address receiver,) = CurveFactory(factory).create(poolId);

            vaults[i] = RewardVault(vault);
            receivers[i] = RewardReceiver(receiver);
        }
    }

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
        try ILiquidityGauge(gauge).integrate_fraction(config.base.locker) returns (uint256 fraction) {
            currentIntegrateFraction = fraction;
        } catch {
            // Fallback if mocked and reverts
            currentIntegrateFraction = IMinter(config.base.minter).minted(config.base.locker, gauge);
        }

        // Add the new amount to existing state (incremental)
        uint256 newIntegrateFraction = currentIntegrateFraction + amount;

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, config.base.locker),
            abi.encode(newIntegrateFraction)
        );
    }
}