// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "src/fx/accumulator/FXNAccumulatorV3.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

contract FXNAccumulatorV3IntegrationTest is Test {
    uint256 blockNumber = 20_031_924;

    ERC20 public WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    address internal locker = FXN.LOCKER;
    address internal sdToken = FXN.SDTOKEN;
    address internal veToken = Fx.VEFXN;

    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(FXN.GAUGE);

    FXNAccumulatorV3 internal accumulator;

    address internal treasuryRecipient = DAO.TREASURY;
    address internal liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(forkId);

        /// Deploy Accumulator Contract.
        accumulator = new FXNAccumulatorV3(address(liquidityGauge), locker, address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitBps = new uint256[](2);

        feeSplitReceivers[0] = treasuryRecipient;
        feeSplitReceivers[1] = liquidityFeeRecipient;

        feeSplitBps[0] = 500;
        feeSplitBps[1] = 1000;

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitBps);

        vm.prank(ILocker(locker).governance());
        ILocker(locker).setAccumulator(address(accumulator));

        vm.prank(liquidityGauge.admin());
        liquidityGauge.set_reward_distributor(address(WSTETH), address(accumulator));

        vm.prank(liquidityGauge.admin());
        liquidityGauge.add_reward(address(FXN.TOKEN), address(accumulator));
    }


    function test_setup() public view {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(WSTETH));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(FXN.TOKEN));
        assertEq(rewardData.distributor, address(accumulator));

        FXNAccumulatorV3.Split memory split = accumulator.getFeeSplit();

        assertEq(split.receivers[0], treasuryRecipient);
        assertEq(split.receivers[1], liquidityFeeRecipient);

        assertEq(split.fees[0], 500);
        assertEq(split.fees[1], 1000);
    }
}
