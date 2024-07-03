// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "test/utils/Utils.sol";
import "src/curve/depositor/CRVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {IDepositor} from "src/base/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISmartWalletChecker} from "src/base/interfaces/ISmartWalletChecker.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CRVLockerIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    address internal constant POOL = 0xCA0253A98D16e9C1e3614caFDA19318EE69772D0;
    address internal constant OLD_DEPOSITOR = 0xc1e3Ca8A3921719bE0aE3690A0e036feB4f69191;

    IERC20 private token;
    ILocker private locker;
    IVeToken private veToken;

    sdToken internal _sdToken;
    CRVDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    uint256 snapshotBalance;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        token = IERC20(CRV.TOKEN);
        veToken = IVeToken(Curve.VECRV);
        _sdToken = sdToken(CRV.SDTOKEN);
        liquidityGauge = ILiquidityGauge(CRV.GAUGE);

        locker = ILocker(CRV.LOCKER);

        depositor = new CRVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge), POOL);

        vm.prank(locker.governance());
        locker.setStrategy(address(depositor));

        vm.prank(DAO.GOVERNANCE);
        IDepositor(OLD_DEPOSITOR).setSdTokenOperator(address(depositor));

        deal(address(token), address(this), amount);
        vm.startPrank(address(0xBEEF));
        // Mint FXN.
        deal(address(token), address(0xBEEF), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        IVeToken.LockedBalance memory locked = veToken.locked(address(locker));
        snapshotBalance = uint256(int256(locked.amount));

        vm.stopPrank();
    }

    function test_initialization() public view {
        assertEq(depositor.minter(), address(_sdToken));
        assertEq(depositor.gauge(), address(liquidityGauge));
    }

    function test_depositAndMint() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        assertEq(token.balanceOf(address(depositor)), 0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(_sdToken.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 5e15);
    }

    function test_depositAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 5e15);
    }

    function test_depositAndStakeWithoutLock() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);

        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);

        address _random = address(0x123);

        assertEq(_sdToken.balanceOf(address(_random)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);

        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        vm.prank(_random);
        depositor.lockToken();

        assertEq(depositor.incentiveToken(), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);
        assertEq(_sdToken.balanceOf(address(_random)), expectedIncentiveAmount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 5e15);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);

        address _random = address(0x123);

        assertEq(_sdToken.balanceOf(address(_random)), 0);
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
        assertEq(_sdToken.balanceOf(address(_random)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + 200e18, 5e15);
    }

    function test_depositAndStakeWithoutLockIncentivePercent() public {
        depositor.setFees(0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertEq(depositor.incentiveToken(), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);

        address _random = address(0x123);

        assertEq(_sdToken.balanceOf(address(_random)), 0);
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
        assertEq(_sdToken.balanceOf(address(_random)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + 200e18, 5e15);
    }

    function test_swapWithoutStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);

        uint256 minAmount = ICurvePool(POOL).get_dy(0, 1, amount);
        depositor.deposit(amount, minAmount, false, address(this));

        assertEq(token.balanceOf(address(depositor)), 0);
        assertGe(liquidityGauge.balanceOf(address(this)), 0);
        assertGe(_sdToken.balanceOf(address(this)), minAmount);
    }

    function test_swapAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);

        uint256 minAmount = ICurvePool(POOL).get_dy(0, 1, amount);
        depositor.deposit(amount, minAmount, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertGe(liquidityGauge.balanceOf(address(this)), minAmount);
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
        assertEq(_sdToken.operator(), address(depositor));

        depositor.setSdTokenMinterOperator(newOperator);
        assertEq(_sdToken.operator(), address(newOperator));
    }
}
