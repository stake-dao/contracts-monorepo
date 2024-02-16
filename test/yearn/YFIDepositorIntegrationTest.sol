// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "src/yearn/depositor/YFIDepositor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

contract YFIDepositorIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 370 days;

    IERC20 private token;
    address private locker;
    IVeYFI private veToken;

    ISdToken internal sdToken;
    YFIDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    uint256 currentBalance = 0;
    uint256 currentLiquidityGaugeBalance = 0;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19234180);

        token = IERC20(YFI.TOKEN);
        veToken = IVeYFI(Yearn.VEYFI);
        sdToken = ISdToken(YFI.SDTOKEN);
        locker = YFI.LOCKER;

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(YFI.GAUGE);

        depositor = new YFIDepositor(address(token), address(locker), address(sdToken), address(liquidityGauge));

        vm.prank(ILocker(locker).governance());
        ILocker(locker).setYFIDepositor(address(depositor));

        vm.prank(sdToken.operator());
        sdToken.setOperator(address(depositor));

        deal(address(token), address(this), amount);
        vm.startPrank(address(0xBEEF));

        // Mint FXN.
        deal(address(token), address(0xBEEF), amount);
        token.approve(address(depositor), amount);

        currentBalance = IVeYFI(veToken).balanceOf(locker);
        currentLiquidityGaugeBalance = sdToken.balanceOf(address(liquidityGauge));

        vm.stopPrank();
    }

    function test_initialization() public {
        assertEq(depositor.minter(), address(sdToken));
        assertEq(depositor.gauge(), address(liquidityGauge));
    }

    function test_createLockOnlyOnce() public {
        // Mint FXN.
        deal(address(token), address(this), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        vm.expectRevert();
        depositor.createLock(amount);
    }

    function test_depositAndMint() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        assertEq(token.balanceOf(address(depositor)), 0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(sdToken.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance + amount, 14e15);
    }

    function test_depositAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        assertEq(sdToken.balanceOf(address(liquidityGauge)), currentLiquidityGaugeBalance + amount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance + amount, 14e15);
    }

    function test_depositAndStakeWithoutLock() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);

        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance, 14e15);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);
        assertEq(sdToken.balanceOf(address(liquidityGauge)), currentLiquidityGaugeBalance + expectedStakedBalance);

        address _random = address(0x123);

        assertEq(sdToken.balanceOf(address(_random)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);

        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        vm.prank(_random);
        depositor.lockToken();

        assertEq(depositor.incentiveToken(), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);
        assertEq(sdToken.balanceOf(address(_random)), expectedIncentiveAmount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance + amount, 14e15);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance, 1e16);
        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);
        assertEq(sdToken.balanceOf(address(liquidityGauge)), currentLiquidityGaugeBalance + expectedStakedBalance);

        address _random = address(0x123);

        assertEq(sdToken.balanceOf(address(_random)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);

        skip(1);

        deal(address(token), _random, amount);
        vm.startPrank(_random);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, _random);

        vm.stopPrank();

        assertEq(depositor.incentiveToken(), 0);
        assertEq(token.balanceOf(address(depositor)), 0);

        assertEq(liquidityGauge.balanceOf(address(_random)), amount + expectedIncentiveAmount);
        assertEq(sdToken.balanceOf(address(_random)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance + 200e18, 1e16);
    }

    function test_depositAndStakeWithoutLockIncentivePercentS() public {
        depositor.setFees(0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance, 1e16);
        assertEq(depositor.incentiveToken(), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        assertEq(sdToken.balanceOf(address(liquidityGauge)), currentLiquidityGaugeBalance + amount);

        address _random = address(0x123);

        assertEq(sdToken.balanceOf(address(_random)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);

        skip(1);

        deal(address(token), _random, amount);
        vm.startPrank(_random);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, _random);

        vm.stopPrank();

        assertEq(depositor.incentiveToken(), 0);
        assertEq(token.balanceOf(address(depositor)), 0);

        assertEq(liquidityGauge.balanceOf(address(_random)), amount);
        assertEq(sdToken.balanceOf(address(_random)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), currentBalance + 200e18, 1e16);

        IVeYFI.LockedBalance memory lockedBalance = veToken.locked(address(locker));

        console.log(lockedBalance.end);
    }

    function test_transferGovernance() public {
        address newGovernance = address(0x123);

        depositor.transferGovernance(newGovernance);

        assertEq(depositor.governance(), address(this));
        assertEq(depositor.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        depositor.acceptGovernance();

        assertEq(depositor.governance(), newGovernance);
        assertEq(depositor.futureGovernance(), newGovernance);
    }

    function test_transferOperator() public {
        address newOperator = address(0x123);
        assertEq(sdToken.operator(), address(depositor));

        depositor.setSdTokenMinterOperator(newOperator);
        assertEq(sdToken.operator(), address(newOperator));
    }
}
