// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import "src/fx/locker/FXNLocker.sol";
import "src/fx/depositor/FXNDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ISmartWalletChecker} from "src/base/interfaces/ISmartWalletChecker.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FXNLockerIntegrationTest is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();

    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    FXNLocker private locker;
    IVeToken private veToken;

    sdToken internal _sdToken;
    FXNDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    function setUp() public virtual {
        token = IERC20(AddressBook.FXN);
        veToken = IVeToken(AddressBook.VE_FXN);
        _sdToken = new sdToken("Stake DAO FXN", "sdFXN");

        address liquidityGaugeImpl = vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4.vy");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                liquidityGaugeImpl,
                AddressBook.PROXY_ADMIN,
                abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(_sdToken),
                address(this),
                AddressBook.SDT,
                AddressBook.VE_SDT,
                AddressBook.VE_SDT_BOOST_PROXY,
                AddressBook.SDT_DISTRIBUTOR
                )
                )
            )
        );

        locker = new FXNLocker(address(this), address(token), address(veToken));

        // Whitelist the locker contract
        vm.prank(ISmartWalletChecker(AddressBook.FXN_SMART_WALLET_CHECKER).owner());
        ISmartWalletChecker(AddressBook.FXN_SMART_WALLET_CHECKER).approveWallet(address(locker));

        depositor = new FXNDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

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
