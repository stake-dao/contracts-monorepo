// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";

import "src/base/fee/TreasuryRecipient.sol";
import "src/base/fee/LiquidityFeeRecipient.sol";
import {FxsAccumulatorFraxtal} from "src/frax/fxs/accumulator/FxsAccumulatorFraxtal.sol";

contract DeployFxsAccumulatoFraxtal is Script {
    FxsAccumulatorFraxtal public accumulator;

    address public constant GAUGE = 0x12992595328E52267c95e45B1a97014D6Ddf8683;
    address public constant LOCKER = 0x26aCff2adc9104FE1c26c958dC4C9a5180840c35;
    address public constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant DELEGATION_REGISTRY = 0x098c837FeF2e146e96ceAF58A10F68Fc6326DC4C;
    address internal constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    TreasuryRecipient internal treasuryRecipient;
    LiquidityFeeRecipient internal liquidityFeeRecipient;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        require(block.chainid == 252, "wrong network");

        treasuryRecipient = new TreasuryRecipient(GOVERNANCE);
        liquidityFeeRecipient = new LiquidityFeeRecipient(GOVERNANCE);

        accumulator = new FxsAccumulatorFraxtal(GAUGE, LOCKER, DEPLOYER, DELEGATION_REGISTRY, GOVERNANCE);

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 1000; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        accumulator.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
