// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveLocker} from "@address-book/src/CurveEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveOptimism.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";

import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployOptimism is BaseCurveDeploy {
    // All pool IDs from the old tests
    Config public _config = Config({
        base: BaseConfig({
            chain: "optimism",
            rewardToken: CurveProtocol.CRV,
            locker: address(0),
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            minter: CurveProtocol.FACTORY,
            boostProvider: CurveProtocol.VECRV,
            gaugeController: CurveProtocol.FACTORY,
            oldStrategy: address(0)
        }),
        convex: ConvexConfig({isOnlyBoost: false, cvx: address(0), convexBoostHolder: address(0), booster: address(0)})
    });

    address[] public gauges;

    constructor() BaseCurveDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.L2_SAFE_TREASURY;
    }

    function run() public override {
        super.run();
    }

    function _afterSetup() internal override {
        IChildLiquidityGaugeFactory[] memory factories = new IChildLiquidityGaugeFactory[](1);
        factories[0] = IChildLiquidityGaugeFactory(config.base.gaugeController);

        CurveFactoryL2(factory).setChildLiquidityGaugeFactories(factories);
        super._afterSetup();

        gauges = getGauges();

        for (uint256 i = 0; i < gauges.length; i++) {
            CurveFactoryL2(factory).createVault(gauges[i]);
        }
    }

    function getGauges() internal returns (address[] memory) {
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

    function _getSalt(string memory contractType) internal view override returns (bytes32) {
        return keccak256(abi.encodePacked(BASE_SALT, ".", protocolId, ".", contractType, ".V1.0.1"));
    }
}
