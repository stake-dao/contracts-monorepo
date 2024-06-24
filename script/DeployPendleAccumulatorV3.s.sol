// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";

import "src/base/fee/VeSDTRecipient.sol";
import "src/base/fee/TreasuryRecipient.sol";
import "src/base/fee/LiquidityFeeRecipient.sol";
import "src/pendle/accumulator/PendleAccumulatorV3.sol";
import "src/pendle/voters-rewards/VotersRewardsRecipient.sol";

contract DeployPendleAccumulatorV3 is Script {
    PendleAccumulatorV3 internal accumulator;

    VeSDTRecipient internal veSDTRecipient;
    TreasuryRecipient internal treasuryRecipient;
    LiquidityFeeRecipient internal liquidityFeeRecipient;
    VotersRewardsRecipient internal votersRewardsRecipient;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        veSDTRecipient = new VeSDTRecipient(DAO.MAIN_DEPLOYER);
        treasuryRecipient = new TreasuryRecipient(DAO.MAIN_DEPLOYER);
        liquidityFeeRecipient = new LiquidityFeeRecipient(DAO.MAIN_DEPLOYER);
        votersRewardsRecipient = new VotersRewardsRecipient(DAO.MAIN_DEPLOYER);

        veSDTRecipient.allowAddress(DAO.ALL_MIGHT);
        treasuryRecipient.allowAddress(DAO.ALL_MIGHT);
        liquidityFeeRecipient.allowAddress(DAO.ALL_MIGHT);
        votersRewardsRecipient.allowAddress(DAO.ALL_MIGHT);

        veSDTRecipient.transferGovernance(DAO.GOVERNANCE);
        treasuryRecipient.transferGovernance(DAO.GOVERNANCE);
        liquidityFeeRecipient.transferGovernance(DAO.GOVERNANCE);
        votersRewardsRecipient.transferGovernance(DAO.GOVERNANCE);

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
