// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {PendleLocker} from "@address-book/src/PendleBase.sol";
import {PendleProtocol} from "@address-book/src/PendleBase.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";
import {BasePendleDeploy} from "script/pendle/BasePendleDeploy.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

contract DeployBase is BasePendleDeploy {
    Config public _config = Config({
        base: BaseConfig({
            chain: "base",
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
        gauges = new address[](11);
        gauges[0] = 0x4EaE2e40C6612005214ea919cc7653dA853Ed409; // LBTC
        gauges[1] = 0xD5dD84c7b8919DceB09536a0FEf6db9046805127; // rETH
        gauges[2] = 0x483f2e223c58a5eF19c4B32fbC6dE57709749cb3; // cbETH
        gauges[3] = 0x9621342D8fb87359abE8Ab2270f402f202F87b67; // wsuperOETHb
        gauges[4] = 0xEe2058f408A43f6D952Ebd55812b4bf0d1cA8854; // yoETH
        gauges[5] = 0x0a3ff49732B13E11B91F1C8D61C6C9c10Bf5a36c; // cgUSD
        gauges[6] = 0xA6b8cFE75Ca5e1b2A527AA255d10521FAaF24b61; // yvBal-GHO-USR
        gauges[7] = 0x715509Bde846104cF2cCeBF6fdF7eF1BB874Bc45; // USR
        gauges[8] = 0xd7C3CEce4bd8FF41aDE50D59ecE7bc91DC2545c1; // USDz
        gauges[9] = 0x44e2B05B2C17A12b37F11De18000922E64E23faa; // yoUSD
        gauges[10] = 0x53fb20ff03Ef94EF224557CC6262e0f11c20f718; // sKAITO

        return gauges;
    }
}
