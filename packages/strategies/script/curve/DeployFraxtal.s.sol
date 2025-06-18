// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CurveProtocol} from "address-book/src/CurveFraxtal.sol";
import {ConvexProtocol} from "address-book/src/ConvexFraxtal.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeployFraxtal is BaseCurveDeploy {
    Config public _config = Config({
        base: BaseConfig({
            chain: "base-sepolia",
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
        admin = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
        feeReceiver = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    }

    function run() public override {
        super.run();
    }

    function _deployGateway() internal override returns (Safe) {
        return Safe(payable(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6));
    }
}
