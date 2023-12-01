// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {CakeAccumulator} from "src/cake/accumulator/CakeAccumulator.sol";
import {IRevenueSharingPool} from "src/base/interfaces/IRevenueSharingPool.sol";

contract CAKEAccumulatorTest is Test {
    CakeAccumulator public accumulator;

    address public daoFeeRecipient = vm.addr(1);
    address public liquidityFeeRecipient = vm.addr(2);
    address public rewardClaimer = vm.addr(3);

    address[] public revenueSharingPools = [
        0xCaF4e48a4Cb930060D0c3409F40Ae7b34d2AbE2D, // revenue share
        0x9cac9745731d1Cf2B483f257745A512f0938DD01 // veCAKe emission
    ];

    address public constant RSPG = 0x011f2a82846a4E9c62C2FC4Fd6fDbad19147D94A;

    address public constant EXTRA_REWARD = 0x4DB5a66E937A9F4473fA95b1cAF1d1E1D62E29EA; // BNB WH    WETH
    address public constant SD_CAKE_GAUGE = AddressBook.GAUGE_SDCAKE;
    address public constant CAKE_LOCKER = AddressBook.CAKE_LOCKER;
    address public constant CAKE = AddressBook.CAKE;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"), 33960060);
        vm.selectFork(forkId);

        accumulator =
            new CakeAccumulator(SD_CAKE_GAUGE, CAKE_LOCKER, daoFeeRecipient, liquidityFeeRecipient, address(this));
    
        // set accumulator as recipient in cake revenue sharing pool
        bytes memory setRecipientData = abi.encodeWithSignature("setRecipient(address,address)", CAKE_LOCKER, address(accumulator));

        vm.startPrank(ILocker(CAKE_LOCKER).governance());
        ILocker(CAKE_LOCKER).execute(revenueSharingPools[0], 0, setRecipientData);
        ILocker(CAKE_LOCKER).execute(revenueSharingPools[1], 0, setRecipientData);
        ILocker(CAKE_LOCKER).setAccumulator(address(accumulator));
        ICakeLocker(CAKE_LOCKER).setRevenueSharingPoolGateway(RSPG);
        vm.stopPrank();

        // Add CAKE as reward in sdCAKE gauge
        vm.prank(ILiquidityGauge(SD_CAKE_GAUGE).admin());
        ILiquidityGauge(SD_CAKE_GAUGE).add_reward(CAKE, address(accumulator));

        deal(CAKE, address(this), 100e18);
        deal(EXTRA_REWARD, address(accumulator), 100e18);
    }

    function testClaimRewardRspMultiTx() public {
        // transfer rewards in each rsp
        for (uint256 i; i < revenueSharingPools.length; i++) {
            ERC20(CAKE).transfer(revenueSharingPools[i], 50e18);
        }

        // Next friday
        skip(7 days);
        uint256 gaugeBalanceBefore;
        address[] memory rspSingle = new address[](1);
        for (uint256 i; i < revenueSharingPools.length; i++) {
            rspSingle[0] = revenueSharingPools[i];
            gaugeBalanceBefore = ERC20(CAKE).balanceOf(SD_CAKE_GAUGE);
            // call it twice to checkpoint up to now
            vm.startPrank(rewardClaimer);
            accumulator.claimAndNotifyAll(rspSingle, false, false);
            accumulator.claimAndNotifyAll(rspSingle, false, false);
            vm.stopPrank();
            assertGt(ERC20(CAKE).balanceOf(SD_CAKE_GAUGE), gaugeBalanceBefore);
        }
        
        for (uint256 i; i < revenueSharingPools.length; i++) {
            uint256 tokenPerPreviousWeek =
            IRevenueSharingPool(revenueSharingPools[i]).tokensPerWeek((block.timestamp / 1 weeks * 1 weeks) - 1 weeks);
            assertGt(tokenPerPreviousWeek, 0);
        }
    }

    function testClaimRewardRspSingleTx() public {
        // transfer rewards in each rsp
        for (uint256 i; i < revenueSharingPools.length; i++) {
            ERC20(CAKE).transfer(revenueSharingPools[i], 50e18);
        }

        // Next friday
        skip(7 days);
        uint256 gaugeBalanceBefore;
        gaugeBalanceBefore = ERC20(CAKE).balanceOf(SD_CAKE_GAUGE);
        // call it twice to checkpoint up to now
        vm.startPrank(rewardClaimer);
        accumulator.claimAndNotifyAll(revenueSharingPools, false, false);
        accumulator.claimAndNotifyAll(revenueSharingPools, false, false);
        vm.stopPrank();
        _checkFeeSplit(CAKE);
    }

    function testNotifyExtraReward() public {
        // add new extra reward
        vm.prank(ILiquidityGauge(SD_CAKE_GAUGE).admin());
        ILiquidityGauge(SD_CAKE_GAUGE).add_reward(EXTRA_REWARD, address(accumulator));

        assertEq(ERC20(EXTRA_REWARD).balanceOf(SD_CAKE_GAUGE), 0);

        vm.prank(rewardClaimer);
        accumulator.notifyReward(EXTRA_REWARD, false, false);

        _checkFeeSplit(EXTRA_REWARD);
    }

    function _checkFeeSplit(address _token) internal {
        uint256 baseFee = accumulator.BASE_FEE();

        uint256 daoFeeBalance = ERC20(_token).balanceOf(accumulator.daoFeeRecipient());
        uint256 liquidityFeeBalance = ERC20(_token).balanceOf(accumulator.liquidityFeeRecipient());
        uint256 claimerBalance = ERC20(_token).balanceOf(rewardClaimer);
        uint256 gaugeBalance = ERC20(_token).balanceOf(SD_CAKE_GAUGE);
        uint256 totalClaimed = daoFeeBalance + liquidityFeeBalance + claimerBalance + gaugeBalance;

        assertEq(daoFeeBalance, totalClaimed * accumulator.daoFee() / baseFee);
        assertEq(liquidityFeeBalance, totalClaimed * accumulator.liquidityFee() / baseFee);
        assertEq(claimerBalance, totalClaimed * accumulator.claimerFee() / baseFee);
    }
}
