// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ANGLE} from "address-book/lockers/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {AngleVoterV5} from "src/angle/voter/AngleVoterV5.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {IAngleGovernor} from "src/base/interfaces/IAngleGovernor.sol";

contract AngleVoterTest is Test {
    AngleVoterV5 internal newVoter;
    address internal currentVoter = 0xDde0F1755DED401a012617f706c66a59c6917EFD;
    address internal gov = DAO.GOVERNANCE;
    address internal angleLocker = ANGLE.LOCKER;
    address internal angleStrategy;
    IAngleGovernor internal angleGovernor;

    uint256 internal proposalId = 74674120326825897432082177555635413441973396692862767653812918068814714026575;

    uint256 internal currentVotes;

    address internal proposalTarget = 0x09D81464c7293C774203E46E3C921559c8E9D53f;
    bytes internal proposalCalldata =
        hex"8f2a0bb000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001517f00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000c462dbb9ec8cd1630f1728b2cfd2769d09f0dd500000000000000000000000052701bfa0599db6db2b2476075d9a2f4cb77dae30000000000000000000000009ad7e7b0877582e14c17702eecf49018dd6f2367000000000000000000000000ba625b318483516f7483dd2c4706ac92d44dbb2b000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000004e5ea47b8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e5ea47b8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e5ea47b8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004e5ea47b800000000000000000000000000000000000000000000000000000000";
    string internal proposalDescription = "ipfs://QmecwSjj6LAXrgSPuGxfVLiTZtcamPuXRMckASTaFZSD9x";

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 19_061_657);
        vm.selectFork(forkId);

        newVoter = new AngleVoterV5();
        angleGovernor = IAngleGovernor(newVoter.ANGLE_GOVERNOR());
        angleStrategy = newVoter.angleStrategy();

        uint256 snapshot = angleGovernor.proposalSnapshot(proposalId);
        currentVotes = angleGovernor.getVotes(angleLocker, snapshot);
        uint256 proposalDeadline = angleGovernor.proposalDeadline(proposalId);
        assertGt(proposalDeadline, block.timestamp);

        // set new strategy's governance
        bytes memory setGovData = abi.encodeWithSignature("setGovernance(address)", address(newVoter));
        vm.startPrank(gov);
        (bool success,) = AngleVoterV5(currentVoter).execute(angleStrategy, 0, setGovData);
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

    function test_propose_a_proposal() external {
        address[] memory targets = new address[](1);
        targets[0] = proposalTarget;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = proposalCalldata;
        vm.prank(gov);
        uint256 newProposalId = newVoter.propose(targets, values, calldatas, proposalDescription);
        assertGt(angleGovernor.proposalSnapshot(newProposalId), block.timestamp);
    }

    function test_transfer_governance() external {
        assertEq(newVoter.governance(), gov);

        address newGovernance = address(0xFABE);

        vm.prank(gov);
        newVoter.transferGovernance(newGovernance);

        assertEq(newVoter.governance(), gov);
        assertEq(newVoter.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        newVoter.acceptGovernance();

        assertEq(newVoter.governance(), newGovernance);
        assertEq(newVoter.futureGovernance(), address(0));
    }

    function test_set_strategy_governance() external {
        address strategyGov = AngleVoterV5(angleStrategy).governance();
        assertEq(strategyGov, address(newVoter));

        bytes memory setGovData = abi.encodeWithSignature("setGovernance(address)", gov);
        vm.startPrank(gov);
        (bool success,) = newVoter.execute(angleStrategy, 0, setGovData);
        assertTrue(success);

        strategyGov = AngleVoterV5(angleStrategy).governance();
        assertEq(strategyGov, gov);
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
