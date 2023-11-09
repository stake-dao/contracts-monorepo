// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {YearnAccumulatorV2} from "src/yearn/accumulator/YearnAccumulatorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

contract YearnAccumulatorV2Test is Test {
    YearnAccumulatorV2 public accumulator;
    IYearnStrategy public strategy = IYearnStrategy(0x1be150a35bb8233d092747eBFDc75FB357c35168);
    address public yfi;
    ILiquidityGauge public sdYfiLG;
    ILocker public yfiLocker;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address daoFeeRecipient = vm.addr(1);
    address liquidityFeeRecipient = vm.addr(2);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"), 18514500);
        vm.selectFork(forkId);
        yfi = AddressBook.YFI;
        sdYfiLG = ILiquidityGauge(AddressBook.GAUGE_SDYFI);
        yfiLocker = ILocker(AddressBook.YFI_LOCKER);
        accumulator =
        new YearnAccumulatorV2(address(sdYfiLG), address(yfiLocker), daoFeeRecipient, liquidityFeeRecipient, address(strategy), address(this));
        vm.startPrank(GOV);
        sdYfiLG.add_reward(DYFI, address(accumulator));
        sdYfiLG.set_reward_distributor(yfi, address(accumulator));
        strategy.setAccumulator(address(accumulator));
        vm.stopPrank();
        vm.prank(address(strategy));
        // disable the acc actions at locker side
        yfiLocker.setAccumulator(address(0));
    }

    function testDyfiClaim() external {
        assertEq(ERC20(DYFI).balanceOf(address(sdYfiLG)), 0);
        // notify DYFI to the sdDyfi gauge
        accumulator.claimTokenAndNotifyAll(DYFI);
        assertEq(ERC20(DYFI).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(DYFI);
    }

    function testYfiClaim() external {
        assertEq(ERC20(yfi).balanceOf(address(sdYfiLG)), 0);
        // notify YFI to the sdDyfi gauge
        accumulator.claimTokenAndNotifyAll(yfi);
        assertEq(ERC20(yfi).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(yfi);
    }

    function testNotifyReward() external {
        uint256 amountToTopUp = 1e18;
        deal(DYFI, address(accumulator), amountToTopUp);
        accumulator.notifyReward(DYFI);
        assertEq(ERC20(DYFI).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(DYFI);
    }

    function testTransferGovernance() external {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));
        accumulator.transferGovernance(GOV);
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), GOV);
        vm.prank(GOV);
        accumulator.acceptGovernance();
        assertEq(accumulator.governance(), GOV);
    }

    function _checkFeesOnClaim(address _token) internal {
        uint256 gaugeBalance = ERC20(_token).balanceOf(address(sdYfiLG));
        uint256 daoPart = ERC20(_token).balanceOf(daoFeeRecipient);
        uint256 liquidityPart = ERC20(_token).balanceOf(liquidityFeeRecipient);
        uint256 claimerPart = ERC20(_token).balanceOf(address(this));
        uint256 totalClaimed = gaugeBalance + daoPart + liquidityPart + claimerPart;
        assertEq(daoPart, totalClaimed * accumulator.daoFee() / 10_000);
        assertEq(liquidityPart, totalClaimed * accumulator.liquidityFee() / 10_000);
        assertEq(claimerPart, totalClaimed * accumulator.claimerFee() / 10_000);
    }
}
