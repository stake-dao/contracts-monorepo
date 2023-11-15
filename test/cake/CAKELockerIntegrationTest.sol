// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {CakeLocker} from "src/cake/locker/CakeLocker.sol";
import {CAKEDepositor} from "src/cake/depositor/CAKEDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IVeToken} from "src/base/interfaces/IVeToken.sol";

interface IVeCakeUtil {
    function setWhitelistedCallers(address[] memory callers, bool ok) external;
    function owner() external view returns (address);
    function delegateFromCakePool(address _delegator) external;
    function updateDelegator(address _delegator, bool _isDelegator, uint40 _limit) external;
}

contract CAKELockerIntegrationTest is Test {
    uint256 private constant MAX_LOCK_DURATION = (53 * 1 weeks) - 1;

    ERC20 private token;
    CakeLocker private locker;
    IVeToken private veToken;

    sdToken internal _sdToken;
    CAKEDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    // testnet addresses
    address public constant CAKE = 0x8d008B313C1d6C7fE2982F62d32Da7507cF43551;
    address public constant VE_CAKE = 0xD512FDe5b20B136Ffd8E0087194BEf8537dc88AE;
    address public constant CAKE_POOL_HOLDER = 0xA13bb13609c3B9AABB8A4D5B4E9EcbaF502cA56E;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb_testnet"));
        vm.selectFork(forkId);
        VyperDeployer vyperDeployer = new VyperDeployer();
        token = ERC20(CAKE);
        veToken = IVeToken(VE_CAKE);
        _sdToken = new sdToken("Stake DAO CAKE", "sdCAKE");

        bytes memory constructorParams = abi.encode(address(_sdToken), address(this));
        liquidityGauge = ILiquidityGauge(
            vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4XChain.vy", constructorParams)
        );

        locker = new CakeLocker(address(this), address(token), address(veToken));

        // Whitelist the locker contract
        vm.startPrank(IVeCakeUtil(VE_CAKE).owner());
        address[] memory callers = new address[](1);
        callers[0] = address(locker);
        IVeCakeUtil(VE_CAKE).setWhitelistedCallers(callers, true);
        // set the locker contract as delegator
        IVeCakeUtil(VE_CAKE).updateDelegator(address(locker), true, 0);
        vm.stopPrank();

        depositor = new CAKEDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        deal(address(token), address(this), amount);

        vm.startPrank(address(0xBEEF));
        // Mint CAKE.
        deal(address(token), address(0xBEEF), amount);
        ERC20(address(token)).approve(address(depositor), amount);

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
        // Mint CAKE.
        deal(address(token), address(this), amount);
        ERC20(address(token)).approve(address(depositor), amount);

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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 196e18, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 196e18, 5e15);
    }

    function test_depositAndStakeWithoutLock() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);

        assertEq(depositor.incentiveToken(), expectedIncentiveAmount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), 98e18, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 196e18, 5e15);
    }

    function test_depositAndStakeWithoutLockThenDepositWith() public {
        uint256 expectedIncentiveAmount = amount * 10 / 10_000;
        uint256 expectedStakedBalance = amount - expectedIncentiveAmount;

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), 98e18, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 295e18, 5e15);
    }

    function test_depositAndStakeWithoutLockIncentivePercent() public {
        depositor.setFees(0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, false, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(depositor)), amount);
        assertApproxEqRel(veToken.balanceOf(address(locker)), 98e18, 5e15);
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

        assertApproxEqRel(veToken.balanceOf(address(locker)), 295e18, 5e15);
    }

    function test_migrationFromCakePool() public {
        assertEq(liquidityGauge.balanceOf(CAKE_POOL_HOLDER), 0);
        vm.prank(CAKE_POOL_HOLDER);
        IVeCakeUtil(VE_CAKE).delegateFromCakePool(address(locker));
        assertGt(liquidityGauge.balanceOf(CAKE_POOL_HOLDER), 0);
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
