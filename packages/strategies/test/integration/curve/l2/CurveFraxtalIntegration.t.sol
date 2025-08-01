// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveL2Integration.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveProtocol} from "@address-book/src/CurveFraxtal.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";
import {CurveFactoryL2} from "src/integrations/curve/L2/CurveFactoryL2.sol";

contract CurveFraxtalIntegrationTest is CurveL2Integration {
    Config public _config = Config({
        base: BaseConfig({
            chain: "frax",
            blockNumber: 22_939_857,
            rewardToken: CurveProtocol.CRV,
            locker: address(0),
            protocolId: bytes4(keccak256("CURVE")),
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            minter: CurveProtocol.FACTORY,
            boostProvider: CurveProtocol.VECRV,
            gaugeController: CurveProtocol.FACTORY,
            oldStrategy: address(0)
        }),
        convex: ConvexConfig({
            isOnlyBoost: true,
            cvx: CurveProtocol.CONVEX_TOKEN,
            convexBoostHolder: CurveProtocol.CONVEX_PROXY,
            booster: CurveProtocol.CONVEX_BOOSTER
        })
    });

    // All pool IDs from the old tests
    uint256[] public poolIds = [9, 18, 13, 15];

    constructor() CurveL2Integration(_config) {}

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);

        IL2Booster booster = IL2Booster(CurveProtocol.CONVEX_BOOSTER);

        for (uint256 i = 0; i < poolIds.length; i++) {
            uint256 poolId = poolIds[i];

            // Get gauge for this pool and set up extra rewards
            (, address gauge,,,) = booster.poolInfo(poolId);
            _setupGaugeExtraRewards(gauge);

            /// Deploy the vault and receiver.
            (address vault, address receiver,) = CurveFactoryL2(factory).create(poolId);

            vaults[i] = RewardVault(vault);
            receivers[i] = RewardReceiver(receiver);
        }
    }

    function _afterSetup() internal override {
        super._afterSetup();

        IChildLiquidityGaugeFactory[] memory childLiquidityGaugeFactories = new IChildLiquidityGaugeFactory[](1);
        childLiquidityGaugeFactories[0] = IChildLiquidityGaugeFactory(config.base.gaugeController);

        CurveFactoryL2(factory).setChildLiquidityGaugeFactories(childLiquidityGaugeFactories);
    }

    function getGauges() internal view override returns (address[] memory) {
        // Get gauge addresses for all pool IDs
        IL2Booster booster = IL2Booster(CurveProtocol.CONVEX_BOOSTER);
        address[] memory gauges = new address[](poolIds.length);

        for (uint256 i = 0; i < poolIds.length; i++) {
            (, address gauge,,,) = booster.poolInfo(poolIds[i]);
            gauges[i] = gauge;
        }

        return gauges;
    }

    function getHarvestableRewards(RewardVault vault) internal override returns (uint256) {}

    function simulateRewards(RewardVault vault, uint256 amount) internal override {
        address locker = config.base.locker;
        if (locker == address(0)) locker = address(gateway);

        address gauge = vault.gauge();
        address minter = ILiquidityGauge(gauge).factory();

        uint256 currentMinterBalance = _balanceOf(address(rewardToken), minter);

        // Make sure the minter has enough balance to mint the new amount
        deal(address(rewardToken), minter, currentMinterBalance + amount);

        // Get the current integrate_fraction (might be mocked from previous calls)
        uint256 currentIntegrateFraction;
        try ILiquidityGauge(gauge).integrate_fraction(locker) returns (uint256 fraction) {
            currentIntegrateFraction = fraction;
        } catch {
            // Fallback if mocked and reverts
            currentIntegrateFraction = IMinter(minter).minted(locker, gauge);
        }

        // Add the new amount to existing state (incremental)
        uint256 newIntegrateFraction = currentIntegrateFraction + amount;

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, locker),
            abi.encode(newIntegrateFraction)
        );
    }
}
