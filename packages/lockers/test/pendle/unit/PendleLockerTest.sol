// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {IVePendle} from "src/base/interfaces/IVePendle.sol";
import {PendleLocker} from "src/pendle/locker/PendleLocker.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {PendleDepositor} from "src/pendle/depositor/PendleDepositor.sol";

contract PendleLockerTest is Test {
    IERC20 internal _PENDLE;
    PendleLocker internal pendleLocker;
    IVePendle internal vePendle;
    PendleDepositor internal depositor;
    sdToken internal sdPendle;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        _PENDLE = IERC20(PENDLE.TOKEN);
        vePendle = IVePendle(Pendle.VEPENDLE);

        // Deploy and Intialize the PendleLocker contract
        pendleLocker = new PendleLocker(address(this), address(this));
        // Deploy sdPendle
        sdPendle = new sdToken("sdPendle", "sdPendle");

        // Deploy and Intialize the Pendle Depositor contract
        depositor = new PendleDepositor(address(_PENDLE), address(pendleLocker), address(sdPendle));
        sdPendle.setOperator(address(depositor));

        pendleLocker.setPendleDepositor(address(depositor));
        // Mint PENDLE to the PendleLocker contract
        deal(address(_PENDLE), address(pendleLocker), 100e18);
    }

    function testCreateLock() public {
        uint128 lockTime = uint128(((block.timestamp + 104 * 1 weeks) / 1 weeks) * 1 weeks);
        pendleLocker.createLock(100e18, lockTime);
        assertApproxEqRel(vePendle.balanceOf(address(pendleLocker)), 100e18, 1e16); // 1% Margin of Error
    }

    function testIncreaseLockAmount() public {
        uint128 lockTime = (uint128(block.timestamp + 104 * 1 weeks) / uint128(1 weeks)) * uint128(1 weeks);
        pendleLocker.createLock(100e18, lockTime);

        (uint256 lockedBalance,) = vePendle.positionData(address(pendleLocker));

        assertEq(lockedBalance, 100e18);

        deal(address(_PENDLE), address(pendleLocker), 100e18);
        pendleLocker.increaseAmount(100e18);

        (lockedBalance,) = vePendle.positionData(address(pendleLocker));
        assertEq(lockedBalance, 200e18);
    }

    function testIncreaseLockDuration() public {
        uint128 initialUnlockTime = (uint128(block.timestamp + 365 days) / uint128(1 weeks)) * uint128(1 weeks);
        uint128 newUnlockTime = (uint128(block.timestamp + 104 * 1 weeks) / uint128(1 weeks)) * uint128(1 weeks);

        pendleLocker.createLock(100e18, initialUnlockTime);
        (, uint128 end) = vePendle.positionData(address(pendleLocker));

        assertEq(end, initialUnlockTime);

        pendleLocker.increaseUnlockTime(newUnlockTime);

        (, end) = vePendle.positionData(address(pendleLocker));

        assertEq(end, newUnlockTime);
    }

    function testDepositViaDepositor() public {
        uint128 lockTime = (uint128(block.timestamp + 104 * 1 weeks) / uint128(1 weeks)) * uint128(1 weeks);
        pendleLocker.createLock(100e18, lockTime);

        deal(address(_PENDLE), address(this), 100e18);
        _PENDLE.approve(address(depositor), 100e18);
        depositor.deposit(100e18, true, false, address(this));
        uint256 sdPendleBalance = sdPendle.balanceOf(address(this));
        assertApproxEqRel(sdPendleBalance, 100e18, 1e16); // 1% Margin of Error
    }

    function testIncreaseLockDurationViaDepositor() public {
        uint128 lockTime = (uint128(block.timestamp + 104 * 1 weeks) / uint128(1 weeks)) * uint128(1 weeks);
        pendleLocker.createLock(100e18, lockTime);

        vm.warp(block.timestamp + 52 * 1 weeks); //extend 52 weeks

        deal(address(_PENDLE), address(this), 100e18);
        _PENDLE.approve(address(depositor), 100e18);
        depositor.deposit(100e18, true, false, address(this));
        (, uint128 end) = vePendle.positionData(address(pendleLocker));
        uint128 expectedEnd = (uint128(block.timestamp + 104 * 1 weeks) / uint128(1 weeks)) * uint128(1 weeks);
        assertEq(end, expectedEnd);
    }

    function testClaimReward() public {
        address[] memory pools = new address[](1);
        pools[0] = address(vePendle);
        // test the correctness of the call
        pendleLocker.claimRewards(address(this), pools);
    }
}
