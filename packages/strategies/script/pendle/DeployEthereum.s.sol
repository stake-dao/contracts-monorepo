// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {PendleLocker, PendleProtocol} from "@address-book/src/PendleEthereum.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";
import {BasePendleDeploy} from "script/pendle/BasePendleDeploy.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

contract DeployEthereum is BasePendleDeploy {
    Config public _config = Config({
        base: BaseConfig({
            chain: "mainnet",
            rewardToken: PendleLocker.TOKEN,
            locker: PendleLocker.LOCKER,
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            gaugeController: PendleProtocol.GAUGE_CONTROLLER,
            oldStrategy: PendleLocker.STRATEGY
        })
    });

    constructor() BasePendleDeploy(_config) {
        admin = CommonUniversal.DEPLOYER_1;
        feeReceiver = DAO.TREASURY;
    }

    function getGauges() internal pure override returns (address[] memory gauges) {
        gauges = new address[](85);
        gauges[0] = 0x4C6c233b16fD3f9C4EC139174Ca8eE8BA0eB8A88;
        gauges[1] = 0xdA57ABF95a7C21eB9df08fBAADa182F749F6C62F;
        gauges[2] = 0x47306E3Cb4E325042556864B38aA0CBE8D928bE5;
        gauges[3] = 0xBaA5aED0aFD90390F00B1915744Ad7e3296FB880;
        gauges[4] = 0x4F76C940fc4F11A621CC0f04b51bD5f61D50984d;
        gauges[5] = 0xCb6F35008f4DE72733dB10D1F24200fA2EC44eb3;
        gauges[6] = 0x45F163E583D34b8E276445dd3Da9aE077D137d72;
        gauges[7] = 0x701C3eFDA4e90Be78Dd63cc0493d2e9B7D2245a6;
        gauges[8] = 0x8AF9872eeE05c7Ca1c24295426E4d71b4AF5B559;
        gauges[9] = 0x71d4a6bAc0FE7210309b6A3807cf2BaD13d7C1E1;
        gauges[10] = 0x55F06992E4C3ed17Df830dA37644885c0c34EDdA;
        gauges[11] = 0x2f8159644f045A388c1FC954e795202Dc1d34308;
        gauges[12] = 0x50700eEDdE7850B4bf83733C66b272C6CA46c663;
        gauges[13] = 0x577afF6DDaD1d25ee18FEE16DE7037dE44F2f5E8;
        gauges[14] = 0x1047a4D2dC60e6652B51e7c63bA276b501ad6bc8;
        gauges[15] = 0xc65B7a0f8Fc97e1D548860d866f4304E039EF016;
        gauges[16] = 0xf4C449d6a2D1840625211769779ADA42857d04dD;
        gauges[17] = 0x8322B96F7aFF9Bf405A5A321C7CA5aaC748716e0;
        gauges[18] = 0x4708E55da780a953FDed696CecB0E19164bA72f4;
        gauges[19] = 0x07b1711d4af74Af661DDe3b774741993B79fC59C;
        gauges[20] = 0x51026Ab8B54767e67f7f5543C86bF718cf00Cb4C;
        gauges[21] = 0xE93B4A93e80BD3065B290394264af5d82422ee70;
        gauges[22] = 0x2353193fa14A6477a4523e2C078e4063022FCf66;
        gauges[23] = 0x688b8eea04B9756da290C962bfBA988b11fC66dF;
        gauges[24] = 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4;
        gauges[25] = 0xa8F21c9D0aFb46382EAD7C33e79f00eF9666e122;
        gauges[26] = 0x992D1E72b9C6b7b80747c56770C660E5eF7d5eC9;
        gauges[27] = 0x9bc2fb257e00468fE921635fe5a73271F385d0EB;
        gauges[28] = 0x23f0dEcc26ecEeafa5CC900F8B47D99FF94DDD2B;
        gauges[29] = 0x3F53eb4c57c7E7118BE8566bCd503EA502639581;
        gauges[30] = 0x33BdA865c6815c906e63878357335B28f063936c;
        gauges[31] = 0xbdEb620F52799856a203Ca0b5de90769C83E3b90;
        gauges[32] = 0x358e4Ced73861514Bc4918EEC59C0BA729b8CcF5;
        gauges[33] = 0xC88FF954d42d3e11D43B62523B3357847C29377c;
        gauges[34] = 0x461bc2ac3f80801BC11B0F20d63B73feF60C8076;
        gauges[35] = 0x446c8AB198C848871c767aDd10a8938A259e9ff6;
        gauges[36] = 0xdacE1121e10500e9e29d071F01593fD76B000f08;
        gauges[37] = 0xbdf3EA4673116698219c08A9AD6B51e4E68d22ab;
        gauges[38] = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7;
        gauges[39] = 0xB8091eAA116Dd111FaF072f4Eb94B1e6a14076e1;
        gauges[40] = 0x56C4200915D74A7cae45dFa57aB33725B0439193;
        gauges[41] = 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9;
        gauges[42] = 0xE467c5C54748f0125d729280F90DeD77C4e720a4;
        gauges[43] = 0xb6aC3d5da138918aC4E84441e924a20daA60dBdd;
        gauges[44] = 0xD4f6592DE90024e541187527d7F1dE83F6Cb6a52;
        gauges[45] = 0xBb28865FfDe901c705FB2fDdb351424883A6A441;
        gauges[46] = 0x9A63FA80b5DDFd3Cab23803fdB93ad2c18F3d5aa;
        gauges[47] = 0x1BD78377DFbCA2043e38b692D2E0b32396b4772d;
        gauges[48] = 0x04EEb15A3A96b679eEd0a5F490ef89Ec5477F045;
        gauges[49] = 0xff43e751f2f07BbF84Da1fc1fa12cE116bF447E5;
        gauges[50] = 0x28CEf9526F3Af7A96A10823f79dD7bcE1940791F;
        gauges[51] = 0xE6723992EC43aa6011457bBBed7D6Cd7Db1407B6;
        gauges[52] = 0x14cFB8B051f0b35045AFa79c70f7e4B0b1F32442;
        gauges[53] = 0x80c229544530c2bA693bF7e8A5AA76Ff98705C6E;
        gauges[54] = 0x1821eC9c2D2C13f6b89D21301B93BD8D6667712b;
        gauges[55] = 0xF8094570485B124b4f2aBE98909A87511489C162;
        gauges[56] = 0xab39fb8E28Def89e5df77c2788a811d881D7fC8E;
        gauges[57] = 0xEbF7FD1ec45F505175D92dB4D180B8f323C17875;
        gauges[58] = 0x2e250f3E0Ca772E87f0C9E2aa55254F7Eb82EA58;
        gauges[59] = 0x1a249b03362C1bFFfEa062F3bD7096C58cA07279;
        gauges[60] = 0x28F2C72361f6B7430C5aC30d289265309392901C;
        gauges[61] = 0x0440b356d6c47af727399cD7194def49AC1D9c1E;
        gauges[62] = 0x73d1C0B9B931654a6755d9319d800B8e81Ad27cA;
        gauges[63] = 0x3DAF20E46708E556570159Eaf98eeE53A1A5b8A4;
        gauges[64] = 0x593b67a445E836D0b4e9186D7604C53b0aE6A74b;
        gauges[65] = 0x7da97FbFAA3020f856C60EB4EF068079A9023Aca;
        gauges[66] = 0x2B10CffFC3e49F4aaE294d86072E5D2ec6332118;
        gauges[67] = 0x2d3BBC6e3FfeB584FC34B8C433F7170741Ad75c1;
        gauges[68] = 0x15E434C42AB4c9a62Ed7db53baaF9d255ea51E0E;
        gauges[69] = 0x02c1289dACb6d459FC784236e862bC504C991f81;
        gauges[70] = 0x34280882267ffa6383B363E278B027Be083bBe3b;
        gauges[71] = 0xC9904994EF8d0614314d66800718d2A213502F9b;
        gauges[72] = 0xC7d566F5Cd575FdAd0e982Bd238d9abCf29807ea;
        gauges[73] = 0x2CbB8eFe9a7ff340768A1b672475111672e7527e;
        gauges[74] = 0x69295970dd33B135417C9b866d03C6f59f022f8b;
        gauges[75] = 0xC5ECdAfBEDe3c8436C9C09E60bFFaC3731A9B28E;
        gauges[76] = 0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2;
        gauges[77] = 0xf55Bc75DF5933DD35aAcF3BCA948b0C4630040d1;
        gauges[78] = 0x95a9504f246cd65bf91c2c550a53F7f415227eD1;
        gauges[79] = 0x1B089668c0833BaaF1C523A7Ed3d6D8CCfEE840b;
        gauges[80] = 0x9F4C227b0fB30a02430D573D657c76AC2de4cEE7;
        gauges[81] = 0xefA9339980fFEE3304Af4822B80484BfcC6f35Ee;
        gauges[82] = 0x6c6668df3916AD01e54397F54ba9deDdBaFeEb50;
        gauges[83] = 0xD009A734028e3aa0839eB69DAB4A594AbcfAE728;
        gauges[84] = 0x4c60AB7cE24D4D7268317f44b6DC3d6530864E86;

        return gauges;
    }
}
