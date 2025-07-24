// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {CurveLocker} from "@address-book/src/CurveEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveSonic.sol";
import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";

import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

import "script/curve/BaseCurveDeploy.sol";

contract DeploySonic is BaseCurveDeploy {
    // All pool IDs from the old tests
    Config public _config = Config({
        base: BaseConfig({
            chain: "sonic",
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

        address[] memory gauges = getGauges();

        for (uint256 i = 0; i < gauges.length; i++) {
            CurveFactoryL2(factory).createVault(gauges[i]);
        }
    }

    function getGauges() internal returns (address[] memory) {
        address[] memory gauges = new address[](28);
        gauges[0] = 0x99001D209c6cb5fBb05cc6566eaC07b2BCA68E58;
        gauges[1] = 0xf7816Fa0e0d2B56D799f45BCA8d4bbe836a55422;
        gauges[2] = 0x227651812bE3cAf89569c59Fb92C54af495eF9F5;
        gauges[3] = 0x0BB2D151A7637C46052DDF9831c494C8788C22F3;
        gauges[4] = 0x17C98b61cA0D05e787E4eAe140854f0354dedfAB;
        gauges[5] = 0x72Df7203c4BD00CC48396143E856c125B4ea836D;
        gauges[6] = 0x43eb584A5a57817C63340287B7111c5a58c02193;
        gauges[7] = 0xaBa49D8FD56CE562d40EB860e6A9C117Bed97F71;
        gauges[8] = 0xd0f19bB52707F0a032E95ddd7195e7909A42478e;
        gauges[9] = 0x99bfDb1790d5Ee7c72bCE66BD85c286E204ad35d;
        gauges[10] = 0x3C0980404263Dc1ed51E5756E6b85F006347695D;
        gauges[11] = 0x23101eFcE70fcA66304f86A59EE6ea8669355774;
        gauges[12] = 0x9c8E4Bc051BEFf9894cD0f368f2B51618f663D2B;
        gauges[13] = 0xA58595992F7E80a83b0EA6bf1A88Fb071489c183;
        gauges[14] = 0xC9e28c1aA5F054ed0B4e9f5332c89925959cFd54;
        gauges[15] = 0xCb099C6795CfA2cEAb522d0eC21A66D50F964223;
        gauges[16] = 0xC0ecb768Fa04be3e2AA68e56B00b9F42b8fA2270;
        gauges[17] = 0x77B56bFb21c7Aa6359304ef6d7f5dAbc0b4386C5;
        gauges[18] = 0xb032ff3d343Dcb8B71efaeB3Da092e8926285b5c;
        gauges[19] = 0x0831Ed691a503FF4074135019fF3C655EF46848E;
        gauges[20] = 0x4e9264eB82aa6264b4Bf1e89c5F2a47A2222A143;
        gauges[21] = 0xc5bA4D9201F66973F50B628fcd83212577196AEA;
        gauges[22] = 0x677B4aE98F312BfE87f23B0C19e72552D8171bCA;
        gauges[23] = 0x1Ab8463412e60cA0Ce6BeD4250C9Eb928E2C4BaC;
        gauges[24] = 0x4f1a5388B92BB912498f52321A6C6eCfe1D56C3f;
        gauges[25] = 0xa2F5113776E5a7118E63A15330f18a8fb23A507A;
        gauges[26] = 0x8CB27af91D71010bB48F5412cDE2Bf607009Afa8;
        gauges[27] = 0xb431078f0A26B13cCF0c4f703422855f3088Bc7d;

        return gauges;
    }

    function _deployGateway() internal pure override returns (Safe) {
        return Safe(payable(CurveLocker.LOCKER));
    }

    function _getSalt(string memory contractType) internal view override returns (bytes32) {
        return keccak256(abi.encodePacked(BASE_SALT, ".", protocolId, ".", contractType, ".V1.0.1"));
    }
}
