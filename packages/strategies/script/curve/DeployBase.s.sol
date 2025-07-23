// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveLocker} from "@address-book/src/CurveEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveBase.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";

import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployBase is BaseCurveDeploy {
    // All pool IDs from the old tests
    Config public _config = Config({
        base: BaseConfig({
            chain: "base",
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

    address[] public gauges = [
        0x0Ab801B0c7AC25B8F900F1267A5Fbf9C9F774Afa,
        0xb2135e9B790C50Fa018ca14e4B04BDb4ADd2a61B,
        0x89289DC2192914a9F0674f1E9A17C56456549b8A,
        0x93933FA992927284e9d508339153B31eb871e1f4,
        0x79edc58C471Acf2244B8f93d6f425fD06A439407,
        0x0566c704640de416E3B1747F63efe0C82f4a3dA7,
        0x9da8420dbEEBDFc4902B356017610259ef7eeDD8,
        0xE9c898BA654deC2bA440392028D2e7A194E6dc3e
    ];

    constructor() BaseCurveDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.L2_SAFE_TREASURY;
    }

    function run() public override {
        super.run();
    }

    function _afterSetup() internal override {
        IChildLiquidityGaugeFactory[] memory factories = new IChildLiquidityGaugeFactory[](2);
        factories[0] = IChildLiquidityGaugeFactory(config.base.gaugeController);
        factories[1] = IChildLiquidityGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

        CurveFactoryL2(factory).setChildLiquidityGaugeFactories(factories);
        super._afterSetup();

        for (uint256 i = 0; i < gauges.length; i++) {
            CurveFactoryL2(factory).createVault(gauges[i]);
        }
    }

    function _deployGateway() internal pure override returns (Safe) {
        return Safe(payable(CurveLocker.LOCKER));
    }

    function _getSalt(string memory contractType) internal view override returns (bytes32) {
        return keccak256(abi.encodePacked(BASE_SALT, ".", protocolId, ".", contractType, ".V1.0.1"));
    }
}
