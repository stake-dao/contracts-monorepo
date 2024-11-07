// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";
import "address-book/src/strategies/56.sol";

import "src/bnb/cake/FeeReceiver.sol";

import "src/common/fee/VeSDTRecipient.sol";
import "src/common/fee/TreasuryRecipient.sol";
import "src/common/fee/LiquidityFeeRecipient.sol";

contract Deploy is Script {
    CakeFeeReceiver public feeReceiver;

    VeSDTRecipient public veSDTRecipient;
    TreasuryRecipient public treasuryRecipient;
    LiquidityFeeRecipient public liquidityFeeRecipient;

    function run() public {
        vm.createSelectFork("bnb");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        feeReceiver =
            new CakeFeeReceiver(DAO.MAIN_DEPLOYER, CAKE_STRATEGIES.ERC20_STRATEGY, CAKE_STRATEGIES.V3_STRATEGY);

        address[] memory receivers = new address[](2);
        receivers[0] = CAKE.ACCUMULATOR;
        receivers[1] = address(treasuryRecipient);

        uint256[] memory repartition = new uint256[](2);
        repartition[0] = 3334;
        repartition[1] = 6666;

        feeReceiver.setAccumulator(CAKE.TOKEN, CAKE.ACCUMULATOR);
        feeReceiver.setRepartition(CAKE.TOKEN, receivers, repartition);
        feeReceiver.transferGovernance(DAO.GOVERNANCE);

        veSDTRecipient = new VeSDTRecipient(DAO.MAIN_DEPLOYER);
        treasuryRecipient = new TreasuryRecipient(DAO.MAIN_DEPLOYER);
        liquidityFeeRecipient = new LiquidityFeeRecipient(DAO.MAIN_DEPLOYER);

        veSDTRecipient.allowAddress(DAO.ALL_MIGHT);
        treasuryRecipient.allowAddress(DAO.ALL_MIGHT);
        liquidityFeeRecipient.allowAddress(DAO.ALL_MIGHT);

        veSDTRecipient.transferGovernance(DAO.GOVERNANCE);
        treasuryRecipient.transferGovernance(DAO.GOVERNANCE);
        liquidityFeeRecipient.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
