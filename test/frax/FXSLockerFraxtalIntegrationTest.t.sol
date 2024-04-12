// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "test/utils/Utils.sol";

import {sdFXSFraxtal} from "src/frax/fxs/token/sdFXSFraxtal.sol";
import "src/frax/fxs/locker/FxsLockerFraxtal.sol";
import {FXSDepositorFraxtal} from "src/frax/fxs/depositor/FXSDepositorFraxtal.sol";

import {Constants} from "src/base/utils/Constants.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IVestedFXS} from "src/base/interfaces/IVestedFXS.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {Frax} from "address-book/protocols/252.sol";

contract FXSLockerFraxtalIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    ERC20 private token = ERC20(Frax.FXS);
    FxsLockerFraxtal private locker;
    IVestedFXS private veToken = IVestedFXS(Frax.VEFXS);

    sdFXSFraxtal internal _sdToken;
    FXSDepositorFraxtal private depositor;
    ILiquidityGauge internal liquidityGauge;

    address private constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address private constant DELEGATION_REGISTRY = 0xF5cA906f05cafa944c27c6881bed3DFd3a785b6A;
    address private constant INITIAL_DELEGATE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;

    uint256 private constant amount = 100e18;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        _sdToken = new sdFXSFraxtal(
            "Stake DAO FXS", "sdFXS", LZ_ENDPOINT, address(this), DELEGATION_REGISTRY, INITIAL_DELEGATE
        );

        liquidityGauge = ILiquidityGauge(
            Utils.deployBytecode(
                Constants.LGV4_NATIVE_FRAXTAL_BYTECODE,
                abi.encode(address(_sdToken), address(this), DELEGATION_REGISTRY, INITIAL_DELEGATE)
            )
        );

        locker =
            new FxsLockerFraxtal(address(this), address(token), address(veToken), DELEGATION_REGISTRY, INITIAL_DELEGATE);

        depositor = new FXSDepositorFraxtal(
            address(token),
            address(locker),
            address(_sdToken),
            address(liquidityGauge),
            DELEGATION_REGISTRY,
            INITIAL_DELEGATE
        );

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        // liquidityGauge.add_reward(address(accumulator.WSTETH()), address(accumulator));

        deal(address(token), address(this), amount);

        vm.startPrank(address(0xBEEF));
        // Mint FXS.
        deal(address(token), address(0xBEEF), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        depositor.createLock(amount);

        vm.stopPrank();
    }

    function test_initialization() public {
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
        assertEq(locker.depositor(), address(depositor));

        assertEq(depositor.minter(), address(_sdToken));
        assertEq(depositor.gauge(), address(liquidityGauge));
    }

    function test_createLockOnlyOnce() public {
        // Mint FXS.
        deal(address(token), address(this), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        vm.expectRevert(FxsLockerFraxtal.LockAlreadyCreated.selector);
        depositor.createLock(amount);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18 * 4, 5e15);
    }

    function test_depositAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        assertEq(_sdToken.balanceOf(address(liquidityGauge)), amount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18 * 4, 5e15);
    }

    function test_depositAndStakeWithoutLock() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);

        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount * 4, 5e15);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);
        assertEq(_sdToken.balanceOf(address(liquidityGauge)), expectedStakedBalance);

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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18 * 4, 5e15);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount * 4, 5e15);
        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertEq(liquidityGauge.balanceOf(address(this)), expectedStakedBalance);
        assertEq(_sdToken.balanceOf(address(liquidityGauge)), expectedStakedBalance);

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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 300e18 * 4, 5e15);
    }

    function test_depositAndStakeWithoutLockIncentivePercent() public {
        depositor.setFees(0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount * 4, 5e15);
        assertEq(depositor.incentiveToken(), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        assertEq(_sdToken.balanceOf(address(liquidityGauge)), amount);

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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 300e18 * 4, 5e15);
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
