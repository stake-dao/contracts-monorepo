// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "src/pendle/accumulator/PendleAccumulatorV3.sol";

contract DeployPendleAccumulatorV3 is Script {
    PendleAccumulatorV3 internal accumulator;

    address internal treasuryRecipient = DAO.TREASURY;
    address internal liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;
    address internal votersRewardsRecipient = PENDLE.VOTERS_REWARDS_RECIPIENT;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        accumulator = new PendleAccumulatorV3(PENDLE.GAUGE, PENDLE.LOCKER, DAO.MAIN_DEPLOYER);

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 1000; // 5% to liquidity

        accumulator.setTransferVotersRewards(true);
        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        accumulator.setVotesRewardRecipient(address(votersRewardsRecipient));

        accumulator.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
