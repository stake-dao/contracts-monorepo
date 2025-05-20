// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {MockGateway} from "test/common/MockGateway.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {CurveVoter} from "src/voters/CurveVoter.sol";
import {IVoting, VoterState} from "@interfaces/curve/IVoting.sol";

contract GovCurveVoterTest is Test {
    CurveVoter internal curveVoter;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21_603_167);

        // Deploy the gateway
        address gateway = address(new MockGateway());

        // Deploy the voter
        curveVoter = new CurveVoter(gateway);

        // Set the governance of the locker to the gateway
        address locker = curveVoter.LOCKER();
        vm.prank(ILocker(locker).governance());
        ILocker(locker).setGovernance(gateway);

        // Labels the important addresses
        vm.label(address(curveVoter), "curveVoter");
        vm.label(gateway, "gateway");
        vm.label(locker, "locker");
    }

    function testVote() public {
        // At the block 21_603_167, we can vote for ownership 931
        uint256 voteId = 931;

        // Check if we can vote
        IVoting curveVoterOwnership = IVoting(curveVoter.VOTER_OWNERSHIP());
        VoterState voterState = curveVoterOwnership.getVoterState(voteId, curveVoter.LOCKER());
        assertTrue(voterState == VoterState.Absent, "Invalid initial state");

        // Vote with the Safe Module
        curveVoter.voteOwnership(voteId, curveVoterOwnership.PCT_BASE(), 0);

        // Check if the vote is applied
        // eq to 1 because yea > nay
        voterState = curveVoterOwnership.getVoterState(voteId, curveVoter.LOCKER());
        assertTrue(voterState == VoterState.Yea, "Invalid final state");

        vm.stopPrank();
    }
}
