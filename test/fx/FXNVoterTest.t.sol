// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/fx/voter/FXNVoter.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";
import {DAO} from "address-book/dao/1.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";

contract FXNVoterTest is Test {
    FXNVoter internal voter;

    IGaugeController internal gaugeController = IGaugeController(Fx.GAUGE_CONTROLLER);

    address internal constant GOVERNANCE = DAO.GOVERNANCE;
    address internal constant FXN_LOCKER = FXN.LOCKER;

    struct Vote {
        address gauge;
        uint256 weight;
    }

    Vote[] public votes;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19_618_010);

        voter = new FXNVoter(address(gaugeController), FXN_LOCKER, address(this));

        vm.prank(GOVERNANCE);
        ILocker(FXN.LOCKER).transferGovernance(address(voter));

        voter.acceptLockerGovernance();

        votes.push(Vote(0x61F32964C39Cca4353144A6DB2F8Efdb3216b35B, 0));
        votes.push(Vote(0x5b1D12365BEc01b8b672eE45912d1bbc86305dba, 7500));
    }

    function testSetup() public {
        assertEq(voter.governance(), address(this));
        assertEq(voter.futureGovernance(), address(0));

        /// Transfer back the governance to the DAO.
        voter.transferLockerGovernance(GOVERNANCE);

        vm.prank(GOVERNANCE);
        ILocker(FXN.LOCKER).acceptGovernance();

        assertEq(ILocker(FXN.LOCKER).governance(), GOVERNANCE);
    }

    function test_vote_for_gauge() external {
        address[] memory _gauges = new address[](votes.length);
        uint256[] memory _weights = new uint256[](votes.length);

        for (uint256 i; i < votes.length; i++) {
            _gauges[i] = votes[i].gauge;
            _weights[i] = votes[i].weight;
        }

        skip(1 weeks);
        voter.voteGauges(_gauges, _weights);

        for (uint256 i; i < votes.length; i++) {
            uint256 lastUserVote = gaugeController.last_user_vote(FXN_LOCKER, votes[i].gauge);
            uint256 power = gaugeController.vote_user_slopes(FXN_LOCKER, votes[i].gauge).power;

            assertEq(power, votes[i].weight);
            assertEq(lastUserVote, block.timestamp);
        }
    }

    function test_execute() external {
        // We skip 1 week to avoid the cooldown period.
        skip(1 weeks);

        bytes memory data =
            abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", votes[0].gauge, votes[0].weight);
        (bool success,) = voter.execute(address(gaugeController), 0, data);
        assertTrue(success);

        uint256 lastUserVote = gaugeController.last_user_vote(FXN_LOCKER, votes[0].gauge);
        uint256 power = gaugeController.vote_user_slopes(FXN_LOCKER, votes[0].gauge).power;

        assertEq(power, votes[0].weight);
        assertEq(lastUserVote, block.timestamp);
    }
}
