// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {CurveLocker} from "address-book/src/CurveEthereum.sol";
import {CurveProtocol} from "address-book/src/CurveFraxtal.sol";
import {ConvexProtocol} from "address-book/src/ConvexFraxtal.sol";
import {CommonUniversal} from "address-book/src/CommonUniversal.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployFraxtal is BaseCurveDeploy {
    Config public _config = Config({
        base: BaseConfig({
            chain: "sepolia",
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
            cvx: ConvexProtocol.CVX,
            convexBoostHolder: ConvexProtocol.VOTER_PROXY,
            booster: ConvexProtocol.BOOSTER
        })
    });

    constructor() BaseCurveDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.L2_SAFE_TREASURY;
    }

    function run() public override {
        super.run();
    }

    function _deployGateway() internal override returns (Safe) {
        return Safe(payable(CurveLocker.LOCKER));
    }
}
