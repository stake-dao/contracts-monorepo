// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {Test} from "forge-std/src/Test.sol";
import {CakeGaugeVoter} from "src/CakeGaugeVoter.sol";
import {PancakeswapLocker, PancakeswapProtocol} from "address-book/src/PancakeswapBSC.sol";

interface Safe {
    function enableModule(address module) external;
}

struct VotedSlope {
    uint256 slope;
    uint256 power;
    uint256 end;
}

interface ICakeGaugeController {
    function voteUserSlopes(address gauge, bytes32 hash) external view returns (VotedSlope memory);
}

contract CakeGaugeVoterTest is Test {
    address public constant CAKE_GAUGE_CONTROLLER = PancakeswapProtocol.GAUGE_CONTROLLER;
    address public constant CAKE_LOCKER = PancakeswapLocker.LOCKER;

    CakeGaugeVoter internal cakeGaugeVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("bnb"), 46974558);

        // Deploy the claimer
        cakeGaugeVoter = new CakeGaugeVoter();

        // Authorize the module in the Safe
        vm.startPrank(cakeGaugeVoter.SD_SAFE());
        Safe(cakeGaugeVoter.SD_SAFE()).enableModule(address(cakeGaugeVoter));
        vm.stopPrank();
    }

    function testCakeVote() public {
        // Compute vote params
        uint256 nbGauges = 13;
        address[] memory gaugeAddresses = new address[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);
        uint256[] memory chainIds = new uint256[](nbGauges);

        gaugeAddresses[0] = address(0xA1D4d0E50cbe0B6CbE6f06e192Cb5D00fa248813);
        gaugeAddresses[1] = address(0x7f51c8AaA6B0599aBd16674e2b17FEc7a9f674A1);
        gaugeAddresses[2] = address(0xdD82975ab85E745c84e497FD75ba409Ec02d4739);
        gaugeAddresses[3] = address(0x718a0C0D94f5601C1F0bFd05E71590F81Cf8B414);
        gaugeAddresses[4] = address(0x5308a901E12995f9ebbD76A82712FD4AF97325BF);
        gaugeAddresses[5] = address(0x7ECeC5056b86fD61F27038201dB7586cB1EB2DCF);
        gaugeAddresses[6] = address(0xBC7766aE74f38f251683633d50Cc2C1CD14aF948);
        gaugeAddresses[7] = address(0xa0bec9b22a22caD9D9813Ad861E331210FE6C589);
        gaugeAddresses[8] = address(0x1dE329a4ADF92Fd61c24af18595e10843fc307e3);
        gaugeAddresses[9] = address(0xEd4D5317823Ff7BC8BB868C1612Bb270a8311179);
        gaugeAddresses[10] = address(0x24853895C8864135E77f3b13CF735966f7636f39);
        gaugeAddresses[11] = address(0x172fcD41E0913e95784454622d1c3724f546f849);
        gaugeAddresses[12] = address(0xB1D54d76E2cB9425Ec9c018538cc531440b55dbB);

        weights[0] = 200;
        weights[1] = 1668;
        weights[2] = 1674;
        weights[3] = 0;
        weights[4] = 643;
        weights[5] = 73;
        weights[6] = 214;
        weights[7] = 167;
        weights[8] = 167;
        weights[9] = 93;
        weights[10] = 723;
        weights[11] = 1353;
        weights[12] = 3020;

        chainIds[0] = 56;
        chainIds[1] = 56;
        chainIds[2] = 56;
        chainIds[3] = 42161;
        chainIds[4] = 8453;
        chainIds[5] = 42161;
        chainIds[6] = 1;
        chainIds[7] = 56;
        chainIds[8] = 56;
        chainIds[9] = 1;
        chainIds[10] = 56;
        chainIds[11] = 56;
        chainIds[12] = 56;

        // Exec vote
        cakeGaugeVoter.vote(gaugeAddresses, weights, chainIds);

        // Check votes
        ICakeGaugeController cakeGaugeController = ICakeGaugeController(CAKE_GAUGE_CONTROLLER);
        for (uint256 i = 0; i < nbGauges; i++) {
            address gauge = gaugeAddresses[i];
            uint256 weight = weights[i];
            uint256 chainId = chainIds[i];

            // Compute hash
            bytes32 gauge_hash = keccak256(abi.encodePacked(gauge, chainId));

            // Check vote
            VotedSlope memory votedSlope = cakeGaugeController.voteUserSlopes(CAKE_LOCKER, gauge_hash);
            assertTrue(votedSlope.power == weight);
        }

        vm.stopPrank();
    }
}
