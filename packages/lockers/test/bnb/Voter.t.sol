// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "src/bnb/cake/Voter.sol";
import "address-book/src/lockers/56.sol";
import "address-book/src/protocols/56.sol";
import {DAO} from "address-book/src/dao/56.sol";
import {IGaugeVoting} from "herdaddy/interfaces/pancake/IGaugeVoting.sol";

contract PancakeVoterTest is Test {
    CakeVoter internal voter;

    IGaugeVoting internal gaugeController = IGaugeVoting(Pancake.GAUGE_CONTROLLER);

    address internal constant CAKE_LOCKER = CAKE.LOCKER;
    address internal constant EXECUTOR = CAKE.EXECUTOR;
    address internal constant GOVERNANCE = DAO.GOVERNANCE;

    struct Vote {
        address gauge;
        uint256 weight;
        uint256 chainId;
    }

    Vote[] public votes;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("bnb"), 44_785_284);

        voter = new CakeVoter(address(gaugeController), CAKE_LOCKER, EXECUTOR, GOVERNANCE);

        vm.prank(GOVERNANCE);
        // Voter must be authorized on Executor
        IExecutor(EXECUTOR).allowAddress(address(voter));

        votes.push(Vote(0x714D48cb99b87F274B33A89fBb16EaD191B40b6C, 3479, 42161));
        votes.push(Vote(0x302e26e9bda986709B5F504D3426c2310e6383c6, 0, 56));
        votes.push(Vote(0xc9B415b8331e1Fb0d2f3442Ac8413E279304090f, 0, 56));
        votes.push(Vote(0x4689e3C91036437A46A6c8B62157F58210Ba67a7, 218, 1));
    }

    function test_vote_for_gauge() external {
        bytes32 gaugeHash = keccak256(abi.encodePacked(votes[0].gauge, votes[0].chainId));
        vm.prank(GOVERNANCE);
        voter.voteForGaugeWeights(votes[0].gauge, votes[0].weight, votes[0].chainId, false, false);
        (, uint256 futurePower,) = gaugeController.voteUserSlopes(CAKE_LOCKER, gaugeHash);
        uint256 lastVoteTs = gaugeController.lastUserVote(CAKE_LOCKER, gaugeHash);
        assertEq(lastVoteTs, block.timestamp);
        assertEq(futurePower, votes[0].weight);
        //assertNotEq(currentPower, futurePower);
    }

    function test_vote_for_gauge_no_gov() external {
        vm.expectRevert(CakeVoter.GOVERNANCE.selector);
        voter.voteForGaugeWeights(votes[0].gauge, votes[0].weight, votes[0].chainId, false, false);
    }

    function test_vote_for_gauges() external {
        vm.prank(GOVERNANCE);
        uint256 length = votes.length;
        address[] memory gauges = new address[](length);
        uint256[] memory weights = new uint256[](length);
        uint256[] memory chainIds = new uint256[](length);
        for (uint256 i; i < length; i++) {
            gauges[i] = votes[i].gauge;
            weights[i] = votes[i].weight;
            chainIds[i] = votes[i].chainId;
        }
        voter.voteForGaugeWeightsBulk(gauges, weights, chainIds, false, false);
        bytes32 gaugeHash;
        uint256 futurePower;
        uint256 lastVoteTs;
        for (uint256 i; i < length; i++) {
            gaugeHash = keccak256(abi.encodePacked(votes[i].gauge, votes[i].chainId));
            (, futurePower,) = gaugeController.voteUserSlopes(CAKE_LOCKER, gaugeHash);
            lastVoteTs = gaugeController.lastUserVote(CAKE_LOCKER, gaugeHash);
            assertEq(futurePower, votes[i].weight);
            assertEq(lastVoteTs, block.timestamp);
        }
    }

    function test_vote_for_gauges_no_gov() external {
        address[] memory gauges;
        uint256[] memory weights;
        uint256[] memory chainIds;
        vm.expectRevert(CakeVoter.GOVERNANCE.selector);
        voter.voteForGaugeWeightsBulk(gauges, weights, chainIds, false, false);
    }

    function test_transfer_governance() external {
        address futureGovernance = DAO.MAIN_DEPLOYER;
        assertEq(voter.governance(), GOVERNANCE);
        assertEq(voter.futureGovernance(), address(0));

        vm.prank(GOVERNANCE);
        voter.transferGovernance(futureGovernance);

        assertEq(voter.governance(), GOVERNANCE);
        assertEq(voter.futureGovernance(), futureGovernance);

        vm.prank(futureGovernance);
        voter.acceptGovernance();

        assertEq(voter.governance(), futureGovernance);
        assertEq(voter.futureGovernance(), address(0));
    }

    function test_transfer_governance_no_gov() external {
        vm.expectRevert(CakeVoter.GOVERNANCE.selector);
        voter.transferGovernance(DAO.MAIN_DEPLOYER);
    }

    function test_set_executor() external {
        vm.prank(GOVERNANCE);
        voter.setExecutor(DAO.MAIN_DEPLOYER);

        assertEq(address(voter.executor()), DAO.MAIN_DEPLOYER);
    }

    function test_set_executor_no_gov() external {
        vm.expectRevert(CakeVoter.GOVERNANCE.selector);
        voter.setExecutor(DAO.MAIN_DEPLOYER);
    }
}
