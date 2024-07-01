// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "test/utils/Utils.sol";

import "src/fx/locker/FXNLocker.sol";
import "src/fx/depositor/FXNDepositor.sol";
import "src/fx/accumulator/FXNAccumulator.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISmartWalletChecker} from "src/base/interfaces/ISmartWalletChecker.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FXNLockerIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    FXNLocker private locker;
    IVeToken private veToken;

    sdToken internal _sdToken;
    FXNDepositor private depositor;
    FXNAccumulator private accumulator;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        token = IERC20(FXN.TOKEN);
        veToken = IVeToken(Fx.VEFXN);

        _sdToken = new sdToken("Stake DAO FXN", "sdFXN");
        address liquidityGaugeImpl = Utils.deployBytecode(Constants.LGV4_BYTECODE, "");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                    liquidityGaugeImpl,
                    DAO.PROXY_ADMIN,
                    abi.encodeWithSignature(
                        "initialize(address,address,address,address,address,address)",
                        address(_sdToken),
                        address(this),
                        DAO.SDT,
                        DAO.VESDT,
                        DAO.VESDT_BOOST_PROXY,
                        DAO.LOCKER_SDT_DISTRIBUTOR
                    )
                )
            )
        );

        locker = new FXNLocker(address(this), address(token), address(veToken));

        // Whitelist the locker contract
        vm.prank(ISmartWalletChecker(Fx.SMART_WALLET_CHECKER).owner());
        ISmartWalletChecker(Fx.SMART_WALLET_CHECKER).approveWallet(address(locker));

        depositor = new FXNDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        accumulator =
            new FXNAccumulator(address(liquidityGauge), address(locker), address(this), address(this), address(this));

        locker.setAccumulator(address(accumulator));

        liquidityGauge.add_reward(address(accumulator.WSTETH()), address(accumulator));

        deal(address(token), address(this), amount);

        vm.startPrank(address(0xBEEF));
        // Mint FXN.
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
        assertEq(_sdToken.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);
    }

    function test_depositAndStakeWithoutLock() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);

        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 300e18, 5e15);
    }

    function test_depositAndStakeWithoutLockIncentivePercent() public {
        depositor.setFees(0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), amount, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 300e18, 5e15);
    }

    function test_distributeRewards() public {
        ERC20 _rewardToken = ERC20(accumulator.WSTETH());

        deal(address(_rewardToken), address(this), 1_000e18);
        _rewardToken.transfer(accumulator.FEE_DISTRIBUTOR(), 1_000e18);

        assertEq(_rewardToken.balanceOf(address(this)), 0);
        assertEq(_rewardToken.balanceOf(address(liquidityGauge)), 0);

        skip(2 weeks);

        IFeeDistributor(accumulator.FEE_DISTRIBUTOR()).checkpoint_token();
        IFeeDistributor(accumulator.FEE_DISTRIBUTOR()).checkpoint_total_supply();

        uint256 expectedReward = _snapshotLockerRewards();
        /// 15.5% fee with 10% for liquidity, 5% for the DAO, 0.5% for the claimer.
        /// Since for the purpose of the test it shares the same recipient, we expect 15.5%.
        uint256 expectedFee = expectedReward * 1550 / 10_000;

        accumulator.claimAndNotifyAll(false, false);

        /// Assert that there's rewards to distribute.
        assertGt(expectedReward, 0);

        /// Received from fees.
        /// Assert Approx because wsETH have a 1 wei issue precision on transfer.
        assertApproxEqAbs(_rewardToken.balanceOf(address(this)), expectedFee, 1);

        /// Distributed as rewards.
        assertApproxEqAbs(_rewardToken.balanceOf(address(liquidityGauge)), expectedReward - expectedFee, 2);
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

    function _snapshotLockerRewards() internal returns (uint256 _claimed) {
        ERC20 _rewardToken = ERC20(accumulator.WSTETH());
        address feeDistributor = accumulator.FEE_DISTRIBUTOR();
        uint256 id = vm.snapshot();

        uint256 _balance = _rewardToken.balanceOf(address(locker));

        vm.prank(address(locker));
        IFeeDistributor(feeDistributor).claim();

        _claimed = _rewardToken.balanceOf(address(locker)) - _balance;

        vm.revertTo(id);
    }
}
