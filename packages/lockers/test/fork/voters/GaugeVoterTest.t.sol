// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {BalancerVoter} from "src/voters/BalancerVoter.sol";
import {CurveVoter} from "src/voters/CurveVoter.sol";
import {FraxVoter} from "src/voters/FraxVoter.sol";
import {FXNVoter} from "src/voters/FXNVoter.sol";
import {PendleVoter} from "src/voters/PendleVoter.sol";
import {VoterPermissionManager} from "src/voters/utils/VoterPermissionManager.sol";
import {MockGateway} from "test/common/MockGateway.sol";

struct VeBalance {
    uint128 bias;
    uint128 slope;
}

struct UserPoolData {
    uint64 weight;
    VeBalance vote;
}

interface Safe {
    function enableModule(address module) external;
}

interface CurveGaugeController {
    function last_user_vote(address, address) external view returns (uint256);
}

interface PendleGaugeController {
    function getUserPoolVote(address, address) external view returns (UserPoolData memory);
}

interface IVoter {
    function governance() external view returns (address);
    function setGovernance(address governance) external;
    function transferGovernance(address newGovernance) external;
    function acceptGovernance() external;
}

contract GaugeVoterTest is Test {
    CurveVoter internal curveVoter;
    BalancerVoter internal balancerVoter;
    FraxVoter internal fraxVoter;
    FXNVoter internal fxnVoter;
    PendleVoter internal pendleVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21_875_357);

        // Deploy the gateway
        MockGateway gateway = new MockGateway();

        // Deploy the voters
        curveVoter = new CurveVoter(address(gateway));
        balancerVoter = new BalancerVoter(address(gateway));
        fraxVoter = new FraxVoter(address(gateway));
        fxnVoter = new FXNVoter(address(gateway));
        pendleVoter = new PendleVoter(address(gateway));

        /////// SET LOCKERS GOVERNANCE ///////
        ILocker locker = ILocker(curveVoter.LOCKER());
        vm.prank(locker.governance());
        locker.setGovernance(address(gateway));

        locker = ILocker(balancerVoter.LOCKER());
        vm.prank(locker.governance());
        locker.setGovernance(address(gateway));

        locker = ILocker(fraxVoter.LOCKER());
        vm.prank(locker.governance());
        locker.setGovernance(address(gateway));

        locker = ILocker(fxnVoter.LOCKER());
        vm.prank(locker.governance());
        locker.transferGovernance(address(gateway));
        vm.prank(address(gateway));
        locker.acceptGovernance();

        locker = ILocker(pendleVoter.LOCKER());
        vm.prank(locker.governance());
        locker.setGovernance(address(gateway));

        /////// VOTER -- ALLOW ADDRESS ///////
        vm.prank(curveVoter.governance());
        curveVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        vm.prank(balancerVoter.governance());
        balancerVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        vm.prank(fraxVoter.governance());
        fraxVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        vm.prank(fxnVoter.governance());
        fxnVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        vm.prank(pendleVoter.governance());
        pendleVoter.setPermission(address(this), VoterPermissionManager.Permission.GAUGES_ONLY);

        // labels
        vm.label(address(gateway), "gateway");

        vm.label(address(curveVoter), "CURVE_VOTER");
        vm.label(address(balancerVoter), "BALANCER_VOTER");
        vm.label(address(fraxVoter), "FRAX_VOTER");
        vm.label(address(fxnVoter), "FXN_VOTER");
        vm.label(address(pendleVoter), "PENDLE_VOTER");

        vm.label(curveVoter.CONTROLLER(), "CURVE_GAUGE_CONTROLLER");
        vm.label(balancerVoter.CONTROLLER(), "BALANCER_GAUGE_CONTROLLER");
        vm.label(fraxVoter.CONTROLLER(), "FRAX_GAUGE_CONTROLLER");
        vm.label(fxnVoter.CONTROLLER(), "FXN_GAUGE_CONTROLLER");
        vm.label(pendleVoter.CONTROLLER(), "PENDLE_VOTING_CONTROLLER");

        vm.label(curveVoter.LOCKER(), "CURVE_LOCKER");
        vm.label(balancerVoter.LOCKER(), "BALANCER_LOCKER");
        vm.label(fraxVoter.LOCKER(), "FRAX_LOCKER");
        vm.label(fxnVoter.LOCKER(), "FXN_LOCKER");
        vm.label(pendleVoter.LOCKER(), "PENDLE_LOCKER");
    }

    function testCurveVote() public {
        uint256 nbGauges = 47;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);

        // Init gauge addresses
        gaugeAddresses[0] = address(0xd303994a0Db9b74f3E8fF629ba3097fC7060C331);
        gaugeAddresses[1] = address(0x6eb6B5915432c890dF1999a491A6929998634bAb);
        gaugeAddresses[2] = address(0x4e227d29b33B77113F84bcC189a6F886755a1f24);
        gaugeAddresses[3] = address(0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe);
        gaugeAddresses[4] = address(0xd8b712d29381748dB89c36BCa0138d7c75866ddF);
        gaugeAddresses[5] = address(0xd5f2e6612E41bE48461FDBA20061E3c778Fe6EC4);
        gaugeAddresses[6] = address(0x26F7786de3E6D9Bd37Fcf47BE6F2bC455a21b74A);
        gaugeAddresses[7] = address(0x8B0aBcFC78a5c14520682FCD76A0E52B71126079);
        gaugeAddresses[8] = address(0x2FD602E5B115aFd6Cb662Bebd18F3c49Da4C960B);
        gaugeAddresses[9] = address(0x9755e37A291a37d8a0AB0828699A59b445477514);
        gaugeAddresses[10] = address(0xeE624fCbb0C197E41ffc58999e6D35b9B893533E);
        gaugeAddresses[11] = address(0x8f5e52BE9B7BDe850BA13e40284F63f14677058f);
        gaugeAddresses[12] = address(0xF1bb643F953836725c6E48BdD6f1816f871d3E07);
        gaugeAddresses[13] = address(0x63DC752E11D4c9D0f2160DA20EdF2111FECB0a66);
        gaugeAddresses[14] = address(0xf792934842e86f964bDF19A439797a6e3c9fE17B);
        gaugeAddresses[15] = address(0x5839337bf070Fea56595A5027e83Cd7126b23884);
        gaugeAddresses[16] = address(0xa40C1E9aA3781c74c437212cd0353eAAB3EBBa6F);
        gaugeAddresses[17] = address(0x415F30505368fa1dB82Feea02EB778be04e75907);
        gaugeAddresses[18] = address(0x740BA8aa0052E07b925908B380248cb03f3DE5cB);
        gaugeAddresses[19] = address(0x5ccDe4BEC0F4006c3826b51EDF0D227D12EA33FA);
        gaugeAddresses[20] = address(0x25707E5FE03dEEdc9Bc7cDD118f9d952C496FeBe);
        gaugeAddresses[21] = address(0xD5bE6A05B45aEd524730B6d1CC05F59b021f6c87);
        gaugeAddresses[22] = address(0x8AD6F98184a0cb79887244b4E7e8beB1b4ba26D4);
        gaugeAddresses[23] = address(0xCFc25170633581Bf896CB6CDeE170e3E3Aa59503);
        gaugeAddresses[24] = address(0x4C5a449c6B81b800938EFCCDB41970e9CF9eC478);
        gaugeAddresses[25] = address(0x58F64138BD2893852e72BdE80AA4e6110CFfbe56);
        gaugeAddresses[26] = address(0x16A3a047fC1D388d5846a73ACDb475b11228c299);
        gaugeAddresses[27] = address(0xD7f9111D529ed8859A0d5A1DC1BA7a021b61f22A);
        gaugeAddresses[28] = address(0x8d4Fc7cCB459722Fdc675BfBe6Fa52540bb70A4B);
        gaugeAddresses[29] = address(0xad85FB8A5eD9E2f338d2798A9eEF176D31cA6A57);
        gaugeAddresses[30] = address(0x7970489a543FB237ABab63d62524d8A5CE165B86);
        gaugeAddresses[31] = address(0x856DBb19e0ce8368ab242f96FD424CE63060Cab0);
        gaugeAddresses[32] = address(0x19f9266f349158b54a6D95dCe79297DF670f7F14);
        gaugeAddresses[33] = address(0x6E9a99F8b3e22c3Ee81d888d7e29293E939B6f9C);
        gaugeAddresses[34] = address(0xd51E1Eee15eF7dc924AAA8B82ff2D2E73408F58c);
        gaugeAddresses[35] = address(0x06f691180F643B35E3644a2296a4097E1f577d0d);
        gaugeAddresses[36] = address(0xd03BE91b1932715709e18021734fcB91BB431715);
        gaugeAddresses[37] = address(0x2932a86df44Fe8D2A706d8e9c5d51c24883423F5);
        gaugeAddresses[38] = address(0x1E4B83f6bFE9dbeB6d5b92a5237E5c18a44176f4);
        gaugeAddresses[39] = address(0x298bf7b80a6343214634aF16EB41Bb5B9fC6A1F1);
        gaugeAddresses[40] = address(0x7671299eA7B4bbE4f3fD305A994e6443b4be680E);
        gaugeAddresses[41] = address(0x4717C25df44e280ec5b31aCBd8C194e1eD24efe2);
        gaugeAddresses[42] = address(0xa48A3c91b062ca06Fd0d0569695432EB066f8c7E);
        gaugeAddresses[43] = address(0xae0f794Bc4Cad74739354223b167dbD04A3Ac6A5);
        gaugeAddresses[44] = address(0x0b8750500484629c213437d70001e862685CE2D0);
        gaugeAddresses[45] = address(0xc372CCdD24Bb0753CEB78bBaC4D24EB7dE4aBE4e);
        gaugeAddresses[46] = address(0x5Dd3e384621e00a9fe1868c257c03FA78AE24e47);

        // Init weights
        for (uint256 i = 0; i < nbGauges; i++) {
            weights[i] = 0;
        }

        // Vote
        curveVoter.voteGauges(gaugeAddresses, weights);

        // Check votes
        for (uint256 i; i < nbGauges; i++) {
            assertTrue(checkBasicVotes(curveVoter.CONTROLLER(), curveVoter.LOCKER(), gaugeAddresses[i]));
        }
    }

    function testBalancerVoter() public {
        uint256 nbGauges = 22;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);

        // Init gauge addresses
        gaugeAddresses[0] = address(0xDc2Df969EE5E66236B950F5c4c5f8aBe62035df2);
        gaugeAddresses[1] = address(0x80CD37A62A8A58C4Cbf64003410c5cCC4d01519f);
        gaugeAddresses[2] = address(0xbf65b3fA6c208762eD74e82d4AEfCDDfd0323648);
        gaugeAddresses[3] = address(0x15C84754c7445D0DF6c613f1490cA07654347c1B);
        gaugeAddresses[4] = address(0xf8C85bd74FeE26831336B51A90587145391a27Ba);
        gaugeAddresses[5] = address(0xe77D45b5dE97aC7717E4EdE6bE16E3D805fF02A5);
        gaugeAddresses[6] = address(0xF22c4C0093a13c193A3162d5B50bC92a8ECB58ef);
        gaugeAddresses[7] = address(0xA00DB7d9c465e95e4AA814A9340B9A161364470a);
        gaugeAddresses[8] = address(0xD449Efa0A587f2cb6BE3AE577Bc167a774525810);
        gaugeAddresses[9] = address(0x5aF3B93Fb82ab8691b82a09CBBae7b8D3eB5Ac11);
        gaugeAddresses[10] = address(0x0d1b58fB1fC10F2160178DE1eAE2d520335ee372);
        gaugeAddresses[11] = address(0x5C0F23A5c1be65Fa710d385814a7Fd1Bda480b1C);
        gaugeAddresses[12] = address(0xd75026F8723b94d9a360A282080492d905c6A558);
        gaugeAddresses[13] = address(0x275dF57d2B23d53e20322b4bb71Bf1dCb21D0A00);
        gaugeAddresses[14] = address(0x0021e01B9fAb840567a8291b864fF783894EabC6);
        gaugeAddresses[15] = address(0x1e916950A659Da9813EE34479BFf04C732E03deb);
        gaugeAddresses[16] = address(0x0312AA8D0BA4a1969Fddb382235870bF55f7f242);
        gaugeAddresses[17] = address(0xf7B0751Fea697cf1A541A5f57D11058a8fB794ee);
        gaugeAddresses[18] = address(0xf720e9137baa9C7612e6CA59149a5057ab320cFa);
        gaugeAddresses[19] = address(0x9965713498c74aee49cEf80B2195461F188F24f8);
        gaugeAddresses[20] = address(0x84f7F5cD2218f31B750E7009Bb6fD34e0b945DaC);
        gaugeAddresses[21] = address(0x79eF6103A513951a3b25743DB509E267685726B7);

        // Init weights
        for (uint256 i = 0; i < nbGauges; i++) {
            weights[i] = 0;
        }

        balancerVoter.voteGauges(gaugeAddresses, weights);

        // Check votes
        for (uint256 i; i < nbGauges; i++) {
            assertTrue(checkBasicVotes(balancerVoter.CONTROLLER(), balancerVoter.LOCKER(), gaugeAddresses[i]));
        }
    }

    function testFraxVote() public {
        uint256 nbGauges = 6;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);

        // Init gauge addresses
        gaugeAddresses[0] = address(0x83Dc6775c1B0fc7AaA46680D78B04b4a3d4f5650);
        gaugeAddresses[1] = address(0xE1e697Fd7EC9b3675808Ba8Ad508fD51cac756a3);
        gaugeAddresses[2] = address(0x4c9AD8c53d0a001E7fF08a3E5E26dE6795bEA5ac);
        gaugeAddresses[3] = address(0x6f82A6551cc351Bc295602C3ea99C78EdACF590C);
        gaugeAddresses[4] = address(0x711d650Cd10dF656C2c28D375649689f137005fA);
        gaugeAddresses[5] = address(0xB4fdD7444E1d86b2035c97124C46b1528802DA35);

        // Init weights
        for (uint256 i = 0; i < nbGauges; i++) {
            weights[i] = 0;
        }

        fraxVoter.voteGauges(gaugeAddresses, weights);

        // Check votes
        for (uint256 i; i < nbGauges; i++) {
            assertTrue(checkBasicVotes(fraxVoter.CONTROLLER(), fraxVoter.LOCKER(), gaugeAddresses[i]));
        }
    }

    function testFxnVote() public {
        uint256 nbGauges = 4;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);

        // Init gauge addresses
        gaugeAddresses[0] = address(0xf0A3ECed42Dbd8353569639c0eaa833857aA0A75);
        gaugeAddresses[1] = address(0x61F32964C39Cca4353144A6DB2F8Efdb3216b35B);
        gaugeAddresses[2] = address(0x5b1D12365BEc01b8b672eE45912d1bbc86305dba);
        gaugeAddresses[3] = address(0x9c7003bC16F2A1AA47451C858FEe6480B755363e);

        // Init weights
        for (uint256 i = 0; i < nbGauges; i++) {
            weights[i] = 0;
        }

        fxnVoter.voteGauges(gaugeAddresses, weights);

        // Check votes
        for (uint256 i; i < nbGauges; i++) {
            assertTrue(checkBasicVotes(fxnVoter.CONTROLLER(), fxnVoter.LOCKER(), gaugeAddresses[i]));
        }
    }

    function testPendleVote() public {
        uint256 nbGauges = 13;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint64[] memory weights = new uint64[](nbGauges);

        gaugeAddresses[0] = address(0xcDd26Eb5EB2Ce0f203a84553853667aE69Ca29Ce);
        gaugeAddresses[1] = address(0xE15578523937ed7F08E8F7a1Fa8a021E07025a08);
        gaugeAddresses[2] = address(0xB162B764044697cf03617C2EFbcB1f42e31E4766);
        gaugeAddresses[3] = address(0xB451A36c8B6b2EAc77AD0737BA732818143A0E25);
        gaugeAddresses[4] = address(0xBDb8F9729d3194f75fD1A3D9bc4FFe0DDe3A404c);
        gaugeAddresses[5] = address(0x7561C5CCfe41A26B33944B58C70D6a3CB63E881c);
        gaugeAddresses[6] = address(0x487E1cEF7805CF0225deC3dD0f3044fe0fB70611);
        gaugeAddresses[7] = address(0x70B70Ac0445C3eF04E314DFdA6caafd825428221);
        gaugeAddresses[8] = address(0x82D810ededb09614144900F914e75Dd76700f19d);
        gaugeAddresses[9] = address(0x2C71Ead7ac9AE53D05F8664e77031d4F9ebA064B);
        gaugeAddresses[10] = address(0x7e0209ab6Fa3c7730603B68799BbE9327DAb7E88);
        gaugeAddresses[11] = address(0x4D7356369273c6373E6C5074fe540CB070acfE6b);
        gaugeAddresses[12] = address(0x58612beB0e8a126735b19BB222cbC7fC2C162D2a);

        // Init weights
        for (uint256 i = 0; i < nbGauges; i++) {
            weights[i] = 0;
        }

        // Vote
        pendleVoter.voteGauges(gaugeAddresses, weights);

        // Check votes
        for (uint256 i; i < nbGauges; i++) {
            assertTrue(checkPendleVotes(gaugeAddresses[i]));
        }
    }

    function checkBasicVotes(address gc, address locker, address gauge) internal view returns (bool) {
        uint256 last_vote = CurveGaugeController(gc).last_user_vote(locker, gauge);
        return last_vote == block.timestamp;
    }

    function checkPendleVotes(address gauge) internal view returns (bool) {
        UserPoolData memory userVote =
            PendleGaugeController(pendleVoter.CONTROLLER()).getUserPoolVote(pendleVoter.LOCKER(), gauge);
        return userVote.weight == 0;
    }
}
