// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IVeYFI} from "src/base/interfaces/IVeYFI.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {YearnLocker} from "src/yearn/locker/YearnLocker.sol";
import {IRewardPool} from "src/base/interfaces/IRewardPool.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract YearnLockerTest is Test {
    IERC20 internal YFI;
    IVeYFI internal veYFI;

    IRewardPool internal rewardPool;
    YearnLocker internal yearnLocker;

    function setUp() public virtual {
        YFI = IERC20(AddressBook.YFI);
        veYFI = IVeYFI(AddressBook.VE_YFI);
        rewardPool = IRewardPool(AddressBook.YFI_REWARD_POOL);

        // Deploy and Intialize the YearnLocker contract
        yearnLocker = new YearnLocker(address(this), address(this), AddressBook.VE_YFI, AddressBook.YFI_REWARD_POOL);
        yearnLocker.approveUnderlying();

        // Mint YFI to the YearnLocker contract
        deal(address(YFI), address(yearnLocker), 100e18);
    }

    function testCreateLock() public {
        yearnLocker.createLock(100e18, block.timestamp + 4 * 365 days);
        assertApproxEqRel(veYFI.balanceOf(address(yearnLocker)), 100e18, 1e16); // 1% Margin of Error
    }

    function testIncreaseLockAmount() public {
        yearnLocker.createLock(100e18, block.timestamp + 4 * 365 days);

        IVeYFI.LockedBalance memory lockedBalance = veYFI.locked(address(yearnLocker));
        assertEq(lockedBalance.amount, 100e18);

        deal(address(YFI), address(yearnLocker), 100e18);
        yearnLocker.increaseAmount(100e18);

        lockedBalance = veYFI.locked(address(yearnLocker));
        assertEq(lockedBalance.amount, 200e18);
    }

    function testIncreaseLockDuration() public {
        uint256 initialUnlockTime = block.timestamp + 365 days;
        uint256 newUnlockTime = block.timestamp + 2 * 365 days;

        yearnLocker.createLock(100e18, initialUnlockTime);
        IVeYFI.LockedBalance memory lockedBalance = veYFI.locked(address(yearnLocker));

        // Assert that the Locked End Timestamp is equal to the initialUnlockTime rounded down to week.
        assertEq(lockedBalance.end, (initialUnlockTime / 1 weeks) * 1 weeks);

        yearnLocker.increaseUnlockTime(newUnlockTime);

        lockedBalance = veYFI.locked(address(yearnLocker));

        // Assert that the new Locked End Timestamp is equal to the newUnlockTime rounded down to week.
        assertEq(lockedBalance.end, (newUnlockTime / 1 weeks) * 1 weeks);
    }

    function testWithdrawWithPenalty() public {
        uint256 balanceBefore = YFI.balanceOf(address(this));

        yearnLocker.createLock(100e18, block.timestamp + 365 days);
        yearnLocker.release(address(this));

        uint256 balanceAfter = YFI.balanceOf(address(this));

        assertEq(balanceBefore, 0);
        assertApproxEqRel(balanceAfter, 75e18, 1e16); // 25% penalty
    }

    function testClaimRewards() public {
        uint256 balanceBefore = YFI.balanceOf(address(this));
        deal(address(YFI), address(yearnLocker), 200e18);
        yearnLocker.createLock(200e18, block.timestamp + 365 days);

        vm.warp(block.timestamp + 2 weeks); //extend 2weeks

        // Fill the Reward Pool with YFI.
        deal(address(YFI), address(rewardPool), 200e18);
        rewardPool.checkpoint_token();
        rewardPool.checkpoint_total_supply();

        vm.warp(block.timestamp + 10 days); //extend 10 days

        yearnLocker.claimRewards(address(YFI), address(this));
        uint256 balanceAfterClaim = YFI.balanceOf(address(this));

        assertEq(balanceBefore, 0);
        assertGt(balanceAfterClaim, balanceBefore);
    }
}
