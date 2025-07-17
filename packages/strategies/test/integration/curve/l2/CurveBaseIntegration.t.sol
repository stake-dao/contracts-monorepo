// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveL2Integration.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveProtocol} from "@address-book/src/CurveBase.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";
import {CurveFactory as L2CurveFactory} from "src/integrations/curve/L2/CurveFactory.sol";

contract CurveBaseIntegrationTest is CurveL2Integration {
    Config public _config = Config({
        base: BaseConfig({
            chain: "base",
            blockNumber: 32_587_139,
            rewardToken: CurveProtocol.CRV,
            locker: address(0),
            protocolId: bytes4(keccak256("CURVE")),
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            minter: CurveProtocol.FACTORY,
            boostProvider: CurveProtocol.VECRV,
            gaugeController: CurveProtocol.FACTORY,
            oldStrategy: address(0)
        }),
        convex: ConvexConfig({isOnlyBoost: false, cvx: address(0), convexBoostHolder: address(0), booster: address(0)})
    });

    constructor() CurveL2Integration(_config) {}

    function _afterSetup() internal override {
        super._afterSetup();

        IChildLiquidityGaugeFactory[] memory childLiquidityGaugeFactories = new IChildLiquidityGaugeFactory[](2);
        childLiquidityGaugeFactories[0] = IChildLiquidityGaugeFactory(config.base.gaugeController);
        childLiquidityGaugeFactories[1] = IChildLiquidityGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

        CurveFactory(factory).setChildLiquidityGaugeFactories(childLiquidityGaugeFactories);
    }

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        // Set up extra rewards for all gauges before vault deployment
        for (uint256 i = 0; i < gauges.length; i++) {
            _setupGaugeExtraRewards(gauges[i]);
        }

        // Call parent implementation
        return super.deployRewardVaults();
    }

    function getGauges() internal override returns (address[] memory) {
        gauges = new address[](3);
        gauges[0] = 0x9da8420dbEEBDFc4902B356017610259ef7eeDD8;
        gauges[1] = 0x79edc58C471Acf2244B8f93d6f425fD06A439407;
        gauges[2] = 0x89289DC2192914a9F0674f1E9A17C56456549b8A;

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
