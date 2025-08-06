// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {PendleLocker} from "@address-book/src/PendleBSC.sol";
import {PendleProtocol} from "@address-book/src/PendleBSC.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";
import {BasePendleDeploy} from "script/pendle/BasePendleDeploy.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

contract DeployBase is BasePendleDeploy {
    Config public _config = Config({
        base: BaseConfig({
            chain: "bnb",
            rewardToken: PendleLocker.TOKEN,
            locker: address(0),
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            gaugeController: PendleProtocol.GAUGE_CONTROLLER,
            oldStrategy: address(0)
        })
    });

    constructor() BasePendleDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.L2_SAFE_TREASURY;
    }

    function getGauges() internal pure override returns (address[] memory gauges) {
        gauges = new address[](10);
        gauges[0] = 0x4C6c233b16fD3f9C4EC139174Ca8eE8BA0eB8A88; // uniBTC
        gauges[1] = 0xE616D50e441aa2f6d6CD43eba1b1632AB1B046e6; // xSolvBTC
        gauges[2] = 0x527bE6FA23ff71e3FAf5c2C1511b0531b67a701D; // SolvBTC.BNB
        gauges[3] = 0xBD577dDABb5a1672d3C786726b87A175de652b96; // slisBNBx
        gauges[4] = 0x2Ac20C37B5577e04bB68E239A45f4fb3b4eDb184; // USDF
        gauges[5] = 0x1630d8228588d406767C2225F927154c05d2E2bb; // USR
        gauges[6] = 0xB5B56637810E4d090894785993F4CdD6875D927E; // USDe
        gauges[7] = 0x74c5050a89046c40296a32aeaed31be89d6A6D87; // satUSD+
        gauges[8] = 0x7608eB2fc533343556e443511a2747F605E49C9B; // ynBNBx
        gauges[9] = 0xE08fC3054450053cd341da695f72b18E6110ffFC; // sUSDX
        gauges[10] = 0xfA4B91d63e7cAb716dD049A23C56F70237C6DDBB; // USDe

        return gauges;
    }
}
