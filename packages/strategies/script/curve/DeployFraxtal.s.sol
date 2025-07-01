// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveLocker} from "@address-book/src/CurveEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveFraxtal.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";

import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployFraxtal is BaseCurveDeploy {
    // All pool IDs from the old tests
    Config public _config = Config({
        base: BaseConfig({
            chain: "frax",
            rewardToken: CurveProtocol.CRV,
            locker: address(0),
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

    constructor() BaseCurveDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.L2_SAFE_TREASURY;
    }

    function run() public override {
        super.run();
    }

    function _afterSetup() internal override {
        IChildLiquidityGaugeFactory[] memory factories = new IChildLiquidityGaugeFactory[](2);
        factories[0] = IChildLiquidityGaugeFactory(0xeF672bD94913CB6f1d2812a6e18c1fFdEd8eFf5c);
        factories[1] = IChildLiquidityGaugeFactory(0x0B8D6B6CeFC7Aa1C2852442e518443B1b22e1C52);

        L2CurveFactory(factory).setChildLiquidityGaugeFactories(factories);
        super._afterSetup();

        IL2Booster booster = IL2Booster(CurveProtocol.CONVEX_BOOSTER);
        uint256 size = booster.poolLength();

        for (uint256 i = 0; i < size; i++) {
            (address vault, address receiver,) = CurveFactory(factory).create(i);
        }
    }

    function _deployGateway() internal pure override returns (Safe) {
        return Safe(payable(CurveLocker.LOCKER));
    }
}
