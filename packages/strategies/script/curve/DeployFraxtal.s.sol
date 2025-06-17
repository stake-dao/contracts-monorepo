// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CurveProtocol} from "address-book/src/CurveFraxtal.sol";
import {ConvexProtocol} from "address-book/src/ConvexFraxtal.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployFraxtal is BaseCurveDeploy {
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
            cvx: ConvexProtocol.CVX,
            convexBoostHolder: ConvexProtocol.VOTER_PROXY,
            booster: ConvexProtocol.BOOSTER
        })
    });

    constructor() BaseCurveDeploy(_config) {}

    function run() public override {
        super.run();
    }
}