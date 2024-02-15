// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {CAKE} from "address-book/lockers/56.sol";
import {Pancake} from "address-book/protocols/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {CakeVoter} from "src/cake/voter/CakeVoter.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";

contract CAKEVoterTest is Test {
    CakeVoter internal voter;

    address internal constant EXECUTOR = 0x74B7639503bb632FfE86382af7C5a3121a41613a;

    address internal constant GOVERNANCE = DAO.GOVERNANCE;

    struct Vote {
        address gauge;
        uint256 weight;
        uint256 chainId;
    }

    Vote[] public votes;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"), 36_097_834);
        vm.selectFork(forkId);

        voter = new CakeVoter(Pancake.GAUGE_CONTROLLER, CAKE.LOCKER, EXECUTOR, GOVERNANCE);

        vm.prank(GOVERNANCE);
        IExecutor(EXECUTOR).allowAddress(address(voter));

        votes.push(Vote(0x714D48cb99b87F274B33A89fBb16EaD191B40b6C, 3479, 42161));
        votes.push(Vote(0x302e26e9bda986709B5F504D3426c2310e6383c6, 0, 56));
        votes.push(Vote(0xc9B415b8331e1Fb0d2f3442Ac8413E279304090f, 0, 56));
        votes.push(Vote(0x4689e3C91036437A46A6c8B62157F58210Ba67a7, 218, 1));
    }

    function test_vote_for_gauge() external {
        vm.prank(GOVERNANCE);
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
    }
}
