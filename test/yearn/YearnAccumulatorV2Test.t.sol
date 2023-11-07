// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {YearnAccumulatorV2} from "src/yearn/accumulator/YearnAccumulatorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

contract YearnAccumulatorV2Test is Test {
    YearnAccumulatorV2 public accumulator;
    IYearnStrategy public strategy = IYearnStrategy(0x1be150a35bb8233d092747eBFDc75FB357c35168);
    address public yfi;
    ILiquidityGauge public sdYfiLG;
    ILocker public yfiLocker;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"), 18514500);
        vm.selectFork(forkId);
        yfi = AddressBook.YFI;
        sdYfiLG = ILiquidityGauge(AddressBook.GAUGE_SDYFI);
        yfiLocker = ILocker(AddressBook.YFI_LOCKER);
        accumulator =
        new YearnAccumulatorV2(address(sdYfiLG), address(yfiLocker), address(this), address(this), address(strategy));
        vm.startPrank(GOV);
        sdYfiLG.add_reward(DYFI, address(accumulator));
        sdYfiLG.set_reward_distributor(yfi, address(accumulator));
        strategy.setAccumulator(address(accumulator));
        vm.stopPrank();
        vm.prank(address(strategy));
        yfiLocker.setAccumulator(address(accumulator));
    }

    function testDyfiClaim() external {
        assertEq(IERC20(DYFI).balanceOf(address(sdYfiLG)), 0);
        // notify DYFI to the sdDyfi gauge
        accumulator.claimSingleTokenAndNotifyAll(DYFI);
        assertEq(IERC20(DYFI).balanceOf(address(accumulator)), 0);
        assertGt(IERC20(DYFI).balanceOf(address(sdYfiLG)), 0);
    }

    function testYfiClaim() external {
        assertEq(IERC20(yfi).balanceOf(address(sdYfiLG)), 0);
        // notify YFI to the sdDyfi gauge
        accumulator.claimSingleTokenAndNotifyAll(yfi);
        assertEq(IERC20(yfi).balanceOf(address(accumulator)), 0);
        assertGt(IERC20(yfi).balanceOf(address(sdYfiLG)), 0);
    }
}
