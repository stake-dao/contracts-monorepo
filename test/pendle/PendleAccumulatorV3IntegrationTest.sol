// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "src/pendle/accumulator/PendleAccumulatorV3.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

import "src/base/fee/TreasuryRecipient.sol";
import "src/base/fee/LiquidityFeeRecipient.sol";

contract PendleAccumulatorV3IntegrationTest is Test {
    uint256 blockNumber = 20_031_924;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal locker = PENDLE.LOCKER;
    address internal sdPendle = PENDLE.SDTOKEN;
    address internal vePENDLE = Pendle.VEPENDLE;

    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(PENDLE.GAUGE);

    PendleAccumulatorV3 internal accumulator;
    TreasuryRecipient internal treasuryRecipient;
    LiquidityFeeRecipient internal liquidityFeeRecipient;

    /// Pools where rewards accrued at the block number 20_031_924.
    address[] public _pools = [
        0x4f30A9D41B80ecC5B94306AB4364951AE3170210, // VePendle
        0x107a2e3cD2BB9a32B9eE2E4d51143149F8367eBa,
        0x90c98ab215498B72Abfec04c651e2e496bA364C0,
        0xd7E0809998693fD87E81D51dE1619fd0EE658031,
        0x2Dfaf9a5E4F293BceedE49f2dBa29aACDD88E0C4,
        0x5E03C94Fc5Fb2E21882000A96Df0b63d2c4312e2,
        0x6Ae79089b2CF4be441480801bb741A531d94312b,
        0x952083cde7aaa11AB8449057F7de23A970AA8472,
        0x7dc07C575A0c512422dCab82CE9Ed74dB58Be30C
    ];

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(forkId);

        /// Deploy Accumulator Contract.
        accumulator = new PendleAccumulatorV3(address(liquidityGauge), locker, address(this));

        /// Deploy Fees Recipients.
        treasuryRecipient = new TreasuryRecipient(address(this));
        liquidityFeeRecipient = new LiquidityFeeRecipient(address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(treasuryRecipient);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 1000; // 5% to liquidity

        /// Set Fee split.
        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);

        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.set_reward_distributor(address(WETH), address(accumulator));
        liquidityGauge.set_reward_distributor(address(PENDLE.TOKEN), address(accumulator));
        vm.stopPrank();
    }

    function test_setup() public {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(WETH));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(PENDLE.TOKEN));
        assertEq(rewardData.distributor, address(accumulator));

        PendleAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], address(treasuryRecipient));
        assertEq(split.receivers[1], address(liquidityFeeRecipient));

        assertEq(split.fees[0], 500);
        assertEq(split.fees[1], 1000);
    }
}
