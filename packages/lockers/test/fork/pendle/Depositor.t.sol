// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {PendleLocker, PendleProtocol} from "@address-book/src/PendleEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IDepositor} from "src/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {IVePendle} from "src/interfaces/IVePendle.sol";
import {PendleDepositor} from "src/integrations/pendle/Depositor.sol";

contract DepositorTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;

    uint256 private constant MAX_LOCK_DURATION = 104 weeks;

    address public constant OLD_DEPOSITOR = 0xf7F64f63ec693C6a3A79fCe4b222Bca2595cAcEf;

    IERC20 private token;
    ILocker private locker;
    IVePendle private veToken;

    ISdToken private _sdToken;
    PendleDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    uint256 internal snapshotBalance;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 21_415_198);
        vm.selectFork(forkId);
        token = IERC20(PendleProtocol.PENDLE);
        veToken = IVePendle(PendleProtocol.VEPENDLE);
        _sdToken = ISdToken(PendleLocker.SDTOKEN);
        liquidityGauge = ILiquidityGauge(PendleLocker.GAUGE);

        locker = ILocker(PendleLocker.LOCKER);

        depositor = new PendleDepositor(
            address(token), address(locker), address(_sdToken), address(liquidityGauge), address(locker)
        );

        vm.prank(locker.governance());
        locker.setPendleDepositor(address(depositor));

        address governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
        vm.prank(governance);
        IDepositor(OLD_DEPOSITOR).setSdTokenOperator(address(depositor));

        deal(address(token), address(this), amount);
        vm.startPrank(address(0xBEEF));

        deal(address(token), address(0xBEEF), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        (uint128 _amount,) = veToken.positionData(address(locker));
        snapshotBalance = uint256(_amount);

        vm.stopPrank();
    }

    function test_initialization() public view {
        assertEq(depositor.minter(), address(_sdToken));
        assertEq(depositor.gauge(), address(liquidityGauge));
        assertEq(locker.pendleDepositor(), address(depositor));
    }

    // @TODO: REWRITE ASAP
    function skip_test_depositAndMint() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        assertEq(token.balanceOf(address(depositor)), 0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(_sdToken.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 1e16);
    }

    // @TODO: REWRITE ASAP
    function skip_test_depositAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 1e16);
    }

    // @TODO: REWRITE ASAP
    function skip_test_depositAndStakeWithoutLock() public {
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

        deal(address(token), address(locker), amount);

        vm.prank(_random);
        depositor.lockToken();

        assertEq(depositor.incentiveToken(), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(_random)), 0);
        assertEq(_sdToken.balanceOf(address(_random)), expectedIncentiveAmount);

        /// It should lock only the amount deposited from the depositor.
        assertEq(token.balanceOf(address(locker)), amount);

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + amount, 1e16);
    }

    // @TODO: REWRITE ASAP
    function skip_test_depositAndStakeWithoutLockThenDepositWithLock() public {
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + 200e18, 1e16);
    }

    // @TODO: REWRITE ASAP
    function skip_test_depositAndStakeWithoutLockIncentivePercent() public {
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), snapshotBalance + 200e18, 1e16);
    }

    function test_transferGovernance() public {
        address newGovernance = address(0x123);

        depositor.transferGovernance(newGovernance);

        assertEq(depositor.governance(), address(this));
        assertEq(depositor.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        depositor.acceptGovernance();

        assertEq(depositor.governance(), newGovernance);
        assertEq(depositor.futureGovernance(), address(0));
    }

    function test_transferOperator() public {
        address newOperator = address(0x123);
        assertEq(_sdToken.operator(), address(depositor));

        depositor.setSdTokenMinterOperator(newOperator);
        assertEq(_sdToken.operator(), address(newOperator));
    }
}
