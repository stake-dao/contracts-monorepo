// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveL2Integration.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveProtocol} from "@address-book/src/CurveArbitrum.sol";
import {CurveFactoryL2} from "src/integrations/curve/L2/CurveFactoryL2.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

contract CurveArbitrumIntegrationTest is CurveL2Integration {
    Config public _config = Config({
        base: BaseConfig({
            chain: "arbitrum",
            blockNumber: 361_384_609,
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

    constructor() CurveL2Integration(_config) {}

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);
        address[] memory gauges = getGauges();

        IL2Booster booster = IL2Booster(CurveProtocol.CONVEX_BOOSTER);

        for (uint256 i = 0; i < gauges.length; i++) {
            address gauge = gauges[i];

            _setupGaugeExtraRewards(gauge);

            address vault;
            address receiver;
            uint256 pid = findConvexPoolId(gauge);

            if (pid == type(uint256).max) {
                (vault, receiver) = Factory(factory).createVault(gauge);
            } else {
                (vault, receiver,) = CurveFactoryL2(factory).create(pid);
            }

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

    function getGauges() internal override returns (address[] memory) {
        // gauges = new address[](1);
        gauges = new address[](25);
        gauges[0] = 0xae0f794Bc4Cad74739354223b167dbD04A3Ac6A5;
        gauges[1] = 0xC1b06b52848fd69D4734983d923e0a0101111e21;
        gauges[2] = 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA;
        gauges[3] = 0xF1bb643F953836725c6E48BdD6f1816f871d3E07;
        gauges[4] = 0xBE543fC11B6Eb4aE1A80cb4e06828f06dC3791DA;
        gauges[5] = 0x46cC987dcd1D4D84ea5ecb2ce081ac4913b7C305;
        gauges[6] = 0xAfcD73E242C6D880edFa87b8146825639BDa3881;
        gauges[7] = 0x6E9a99F8b3e22c3Ee81d888d7e29293E939B6f9C;
        gauges[8] = 0x030786336Bc7833D4325404A25FE451e4fde9807;
        gauges[9] = 0x8d1600015aE09eAaCaEd08531a03ecb8f2bD40fA;
        gauges[10] = 0xb12600D06753Df7c706225c901E6C1346A654D0b;
        gauges[11] = 0xad85FB8A5eD9E2f338d2798A9eEF176D31cA6A57;
        gauges[12] = 0x2F8bcdF1824B91D420F8951A972eE988Ebd8544d;
        gauges[13] = 0x7611DDC8b5029184f900a5a1Dca5C1610684F71e;
        gauges[14] = 0x7AE49935b8BC11023e5b04d86a44055f999fca31;
        gauges[15] = 0x8d4Fc7cCB459722Fdc675BfBe6Fa52540bb70A4B;
        gauges[16] = 0x5839337bf070Fea56595A5027e83Cd7126b23884;
        gauges[17] = 0xDa9A503E67A075AF2c3Ea840256b02891535471A;
        gauges[18] = 0x02b8e750E68cb648dB2c2ac4BBb47A10A5c12588;
        gauges[19] = 0x0b8750500484629c213437d70001e862685CE2D0;
        gauges[20] = 0x721cAc0F4715A29aCD76752408636e8A49222C11;
        gauges[21] = 0x4645e6476D3A5595Be9Efd39426cc10586a8393D;
        gauges[22] = 0x059E0db6BF882f5fe680dc5409C7adeB99753736;
        gauges[23] = 0x99178264ec6b9de40689eE4F2f561cA3885a4BD2;
        gauges[24] = 0xB08FEf57bFcc5f7bF0EF69C0c090849d497C8F8A;

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

    function findConvexPoolId(address gauge) internal view returns (uint256) {
        IL2Booster booster = IL2Booster(CurveProtocol.CONVEX_BOOSTER);
        uint256 poolLength = booster.poolLength();

        for (uint256 i = 0; i < poolLength; i++) {
            (, address gaugeAddress,, bool shutdown,) = booster.poolInfo(i);
            if (gaugeAddress == gauge && !shutdown) {
                return i;
            }
        }

        return type(uint256).max; // Return max uint if not found
    }
}
