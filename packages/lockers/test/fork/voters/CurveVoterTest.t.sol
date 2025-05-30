// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IVoting, VoterState} from "@interfaces/curve/IVoting.sol";
import {Test} from "forge-std/src/Test.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {CurveVoter} from "src/integrations/curve/CurveVoter.sol";
import {VoterPermissionManager} from "src/VoterPermissionManager.sol";
import {MockGateway} from "test/common/MockGateway.sol";

contract GovCurveVoterTest is Test {
    CurveVoter internal curveVoter;
    address internal immutable authorizedAddress = makeAddr("caller");

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

        // Set this contract the permission to interact with the voter
        curveVoter.setPermission(authorizedAddress, VoterPermissionManager.Permission.PROPOSALS_ONLY);

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
        uint256 pctBase = curveVoterOwnership.PCT_BASE();
        vm.prank(authorizedAddress);
        curveVoter.voteOwnership(voteId, pctBase, 0);

        // Check if the vote is applied
        // eq to 1 because yea > nay
        voterState = curveVoterOwnership.getVoterState(voteId, curveVoter.LOCKER());
        assertTrue(voterState == VoterState.Yea, "Invalid final state");

        vm.stopPrank();
    }
}
