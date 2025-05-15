// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {Test} from "forge-std/src/Test.sol";
import {GovCurveVoter, ICurveVoter, VoterState} from "../src/GovCurveVoter.sol";
import {CurveLocker} from "address-book/src/CurveEthereum.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

interface Safe {
    function enableModule(address module) external;
}

contract GovCurveVoterTest is Test {
    address public constant DEPLOYER = address(DAO.MAIN_DEPLOYER);
    address public constant SD_CURVE_LOCKER = address(CurveLocker.LOCKER);

    GovCurveVoter govCurveVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21_603_167);

        // Deploy the claimer
        vm.startPrank(DEPLOYER);
        govCurveVoter = new GovCurveVoter();
        vm.stopPrank();

        // Authorize the module in the Safe
        vm.startPrank(govCurveVoter.SD_SAFE());
        Safe(govCurveVoter.SD_SAFE()).enableModule(address(govCurveVoter));
        vm.stopPrank();
    }

    function testVote() public {
        // At the block 21_603_167, we can vote for ownership 931
        uint256 voteId = 931;
        vm.startPrank(DEPLOYER);

        // Check if we can vote
        ICurveVoter curveVoterOwnership = ICurveVoter(govCurveVoter.VOTER_OWNERSHIP());
        VoterState voterState = curveVoterOwnership.getVoterState(voteId, SD_CURVE_LOCKER);
        assertTrue(voterState == VoterState.Absent, "!VoterState");

        // Vote with the Safe Module
        govCurveVoter.voteOwnership(voteId, curveVoterOwnership.PCT_BASE(), 0);

        // Check if the vote is applied
        // eq to 1 because yea > nay
        voterState = curveVoterOwnership.getVoterState(voteId, SD_CURVE_LOCKER);
        assertTrue(voterState == VoterState.Yea, "!VoterState");

        vm.stopPrank();
    }
}
