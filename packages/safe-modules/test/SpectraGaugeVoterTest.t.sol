// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "../src/SpectraGaugeVoter.sol";

interface Safe {
    function enableModule(address module) external;
}

struct VotedSlope {
    uint256 slope;
    uint256 power;
    uint256 end;
}

interface ISpectraVoter {
    function votes(address ve, uint256 tokenId, uint160 poolId) external view returns(uint256);
    function usedWeights(address ve, uint256 tokenId) external view returns(uint256);
}

contract SpectraGaugeVoterTest is Test {
    address public constant DEPLOYER = address(0x428419Ad92317B09FE00675F181ac09c87D16450);

    SpectraGaugeVoter spectraGaugeVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("base"), 30481499);

        // Deploy the claimer
        vm.startPrank(DEPLOYER);
        spectraGaugeVoter = new SpectraGaugeVoter();
        vm.stopPrank();

        // Authorize the module in the Safe
        vm.startPrank(spectraGaugeVoter.SD_SAFE());
        Safe(spectraGaugeVoter.SD_SAFE()).enableModule(address(spectraGaugeVoter));
        vm.stopPrank();
    }

    function testVote() public {
        vm.startPrank(DEPLOYER);

        // Compute vote params
        uint256 nbGauges = 1;
        uint160[] memory pools = new uint160[](nbGauges);
        uint256[] memory weights = new uint256[](nbGauges);

        pools[0] = uint160(1285096718668641499024068352622928265951946908010);

        weights[0] = 1000000000000000000;

        // Exec vote
        spectraGaugeVoter.vote(pools, weights);

        // Check votes
        ISpectraVoter spectraVoter = ISpectraVoter(spectraGaugeVoter.VOTER());
        uint256 usedWeights = spectraVoter.usedWeights(spectraGaugeVoter.VE_SPECTRA(), spectraGaugeVoter.TOKEN_ID());
        
        uint256 totalWeightUsed = 0;
        for(uint256 i = 0; i < nbGauges; i++) {
            totalWeightUsed += spectraVoter.votes(spectraGaugeVoter.VE_SPECTRA(), spectraGaugeVoter.TOKEN_ID(), pools[i]);
        }

        assertTrue(totalWeightUsed == usedWeights);
        
        vm.stopPrank();
    }
}
