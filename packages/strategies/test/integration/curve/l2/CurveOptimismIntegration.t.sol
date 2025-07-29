// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveL2Integration.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveProtocol} from "@address-book/src/CurveOptimism.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";
import {CurveFactoryL2} from "src/integrations/curve/L2/CurveFactoryL2.sol";

contract CurveOptimismIntegrationTest is CurveL2Integration {
    Config public _config = Config({
        base: BaseConfig({
            chain: "optimism",
            blockNumber: 139_088_546,
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

        IChildLiquidityGaugeFactory[] memory childLiquidityGaugeFactories = new IChildLiquidityGaugeFactory[](1);
        childLiquidityGaugeFactories[0] = IChildLiquidityGaugeFactory(config.base.gaugeController);

        CurveFactoryL2(factory).setChildLiquidityGaugeFactories(childLiquidityGaugeFactories);
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
        gauges = new address[](10);
        gauges[0] = 0xcEa806562B757AefFa9fE9D0a03C909b4a204254;
        gauges[1] = 0x172a5AF37f69C69CC59E748D090a70615830A5Dd;
        gauges[2] = 0xCB8883D1D8c560003489Df43B30612AAbB8013bb;
        gauges[3] = 0x4B960396011A914B4ccCC3b33DFEE83A97A9D766;
        gauges[4] = 0x15F52286C0FF1d7A7dDbC9E300dd66628D46D4e6;
        gauges[5] = 0x57eF895Af21A6C4813043e9D04E8A34592951280;
        gauges[6] = 0x393F3d6bBA96dB02C3653D21Ec582b7f843a2668;
        gauges[7] = 0xf9CB3854A922655004022A84Ba1618B1100CBEEf;
        gauges[8] = 0xB280fab4817C54796F9E6147aa1ad0198CFEfb41;
        gauges[9] = 0xc5aE4B5F86332e70f3205a8151Ee9eD9F71e0797;

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
