// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ANGLE} from "address-book/lockers/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {AngleVoterV5} from "src/angle/voter/AngleVoterV5.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {IAngleGovernor} from "src/base/interfaces/IAngleGovernor.sol";

contract AngleVoterTest is Test {
    AngleVoterV5 internal newVoter;
    address internal currentVoter = ANGLE.VOTER;
    address internal gov = DAO.GOVERNANCE;
    address internal angleLocker = ANGLE.LOCKER;
    IAngleGovernor internal angleGovernor;

    uint256 internal proposalId = 74674120326825897432082177555635413441973396692862767653812918068814714026575;

    uint256 internal currentVotes;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 19_061_657);
        vm.selectFork(forkId);

        newVoter = new AngleVoterV5();
        angleGovernor = IAngleGovernor(newVoter.ANGLE_GOVERNOR());
        uint256 snapshot = angleGovernor.proposalSnapshot(proposalId);
        currentVotes = angleGovernor.getVotes(angleLocker, snapshot);
        uint256 proposalDeadline = angleGovernor.proposalDeadline(proposalId);
        assertGt(proposalDeadline, block.timestamp);

        // set new strategy's governance
        bytes memory setGovData = abi.encodeWithSignature("setGovernance(address)", address(newVoter));
        vm.startPrank(gov);
        (bool success,) = IExecutor(currentVoter).execute(newVoter.angleStrategy(), 0, setGovData);
        assertTrue(success);
        vm.stopPrank();
    }

    function test_voter_params() external {
        assertEq(newVoter.ANGLE_LOCKER(), angleLocker);
        assertEq(newVoter.governance(), gov);
    }

    function test_cast_vote_against() external {
        _castVote(0, "", "");
    }

    function test_cast_vote_for() external {
        _castVote(1, "", "");
    }

    function test_cast_vote_abstain() external {
        _castVote(2, "", "");
    }

    function test_cast_vote_with_reason_against() external {
        _castVote(0, "against", "");
    }

    function test_cast_vote_with_reason_for() external {
        _castVote(1, "for", "");
    }

    function test_cast_vote_with_reason_abstain() external {
        _castVote(2, "abstain", "");
    }

    function test_cast_vote_with_reason_and_params_against() external {
        bytes memory params = abi.encodePacked(uint128(currentVotes), uint128(0), uint128(0));
        _castVote(0, "against", params);
    }

    function test_cast_vote_with_reason_and_params_for() external {
        bytes memory params = abi.encodePacked(uint128(0), uint128(currentVotes), uint128(0));
        _castVote(0, "for", params);
    }

    function test_cast_vote_with_reason_and_params_abstain() external {
        bytes memory params = abi.encodePacked(uint128(0), uint128(0), uint128(currentVotes));
        _castVote(0, "abstain", params);
    }

    function test_cast_vote_with_reason_and_votes() external {
        uint128 voteToAllocate = uint128(currentVotes / 3);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = angleGovernor.proposalVotes(proposalId);

        assertFalse(angleGovernor.hasVoted(proposalId, angleLocker));

        vm.prank(gov);
        uint256 weight =
            newVoter.castVoteWithReasonAndParams(proposalId, 0, "mixed", voteToAllocate, voteToAllocate, voteToAllocate);

        assertEq(weight, currentVotes);
        assertTrue(angleGovernor.hasVoted(proposalId, angleLocker));

        (uint256 againstVotesAfterCast, uint256 forVotesAfterCast, uint256 abstainVotesAfterCast) =
            angleGovernor.proposalVotes(proposalId);

        assertEq(againstVotes + voteToAllocate, againstVotesAfterCast);
        assertEq(forVotes + voteToAllocate, forVotesAfterCast);
        assertEq(abstainVotes + voteToAllocate, abstainVotesAfterCast);
    }

    function _castVote(uint8 _support, string memory _reason, bytes memory _params) internal {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = angleGovernor.proposalVotes(proposalId);

        assertFalse(angleGovernor.hasVoted(proposalId, angleLocker));

        vm.prank(gov);
        uint256 weight;
        if (keccak256(abi.encode(_reason)) == keccak256(abi.encode(""))) {
            weight = newVoter.castVote(proposalId, _support);
        } else if (_params.length == 0) {
            weight = newVoter.castVoteWithReason(proposalId, _support, _reason);
        } else {
            weight = newVoter.castVoteWithReasonAndParams(proposalId, _support, _reason, _params);
        }
        assertEq(weight, currentVotes);
        assertTrue(angleGovernor.hasVoted(proposalId, angleLocker));

        (uint256 againstVotesAfterCast, uint256 forVotesAfterCast, uint256 abstainVotesAfterCast) =
            angleGovernor.proposalVotes(proposalId);

        if (_params.length == 0) {
            if (_support == 0) {
                againstVotes += currentVotes;
            } else if (_support == 1) {
                forVotes += currentVotes;
            } else if (_support == 2) {
                abstainVotes += currentVotes;
            }
        } else {
            uint128 againstVoted;
            uint128 forVoted;
            uint128 abstainVoted;
            assembly {
                againstVoted := shr(128, mload(add(_params, 0x20)))
                forVoted := and(0xffffffffffffffffffffffffffffffff, mload(add(_params, 0x20)))
                abstainVoted := shr(128, mload(add(_params, 0x40)))
            }
            againstVotes += againstVoted;
            forVotes += forVoted;
            abstainVotes += abstainVoted;
        }

        assertEq(forVotes, forVotesAfterCast);
        assertEq(abstainVotes, abstainVotesAfterCast);
        assertEq(againstVotes, againstVotesAfterCast);
    }
}
