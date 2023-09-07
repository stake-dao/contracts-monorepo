// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MAVLockerIntegrationTest is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();

    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    MAVLocker private locker;
    IVotingEscrowMav private veToken;

    sdToken internal _sdToken;
    MAVDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    function setUp() public virtual {
        token = IERC20(AddressBook.MAV);
        veToken = IVotingEscrowMav(AddressBook.VE_MAV);
        _sdToken = new sdToken("Stake DAO MAV", "sdMAV");

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

        locker = new MAVLocker(address(this), address(token), address(veToken));
        depositor = new MAVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        // Mint MAV for testing.
        deal(address(token), address(this), amount);

        // Mint MAV to the MAVLocker contract
        deal(address(token), address(locker), amount);

        locker.createLock(amount, MAX_LOCK_DURATION);
    }

    function test_initialization() public {
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
        assertEq(locker.depositor(), address(depositor));

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

        (uint256 expectedBalance,) = veToken.previewPoints(200e18, MAX_LOCK_DURATION);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
    }

    function test_depositAndStake() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        (uint256 expectedBalance,) = veToken.previewPoints(200e18, MAX_LOCK_DURATION);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
        assertEq(_sdToken.balanceOf(address(liquidityGauge)), amount);
    }

    function test_depositAndStakeWithoutLock() public {
        (uint256 expectedBalance,) = veToken.previewPoints(amount, MAX_LOCK_DURATION);

        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
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

        (expectedBalance,) = veToken.previewPoints(200e18, MAX_LOCK_DURATION);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        (uint256 expectedBalance,) = veToken.previewPoints(amount, MAX_LOCK_DURATION);

        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
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

        /// Skip 1 seconds to avoid depositing in the same block as locking.
        (expectedBalance,) = veToken.previewPoints(300e18, MAX_LOCK_DURATION);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
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
