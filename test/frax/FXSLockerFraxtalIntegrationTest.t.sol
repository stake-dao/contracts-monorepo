// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "test/utils/Utils.sol";

import {sdFXSFraxtal} from "src/frax/fxs/token/sdFXSFraxtal.sol";
import {sdTokenOperatorFraxtal} from "src/frax/fxs/token/sdTokenOperatorFraxtal.sol";
import "src/frax/fxs/locker/FxsLockerFraxtal.sol";
import {FXSDepositorFraxtal} from "src/frax/fxs/depositor/FXSDepositorFraxtal.sol";
import {FxsAccumulatorV2Fraxtal} from "src/frax/fxs/accumulator/FxsAccumulatorV2Fraxtal.sol";

import {Constants} from "src/base/utils/Constants.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IVestedFXS} from "src/base/interfaces/IVestedFXS.sol";
import {IFraxtalDelegationRegistry} from "src/base/interfaces/IFraxtalDelegationRegistry.sol";
import {IYieldDistributor} from "src/base/interfaces/IYieldDistributor.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {Frax} from "address-book/protocols/252.sol";
import {FXS} from "address-book/lockers/1.sol";

interface IYieldDistributorWhitelist {
    function owner() external view returns (address);

    function setThirdPartyClaimer(address _staker, address _claimer) external;
}

contract FXSLockerFraxtalIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    ERC20 private token = ERC20(Frax.FXS);
    FxsLockerFraxtal private locker;
    IVestedFXS private veToken = IVestedFXS(Frax.VEFXS);
    //IYieldDistributor private yieldDistributor = IYieldDistributor(Frax.YIELD_DISTRIBUTOR);
    IYieldDistributor private yieldDistributor = IYieldDistributor(0x21359d1697e610e25C8229B2C57907378eD09A2E);

    sdFXSFraxtal private _sdToken;
    sdTokenOperatorFraxtal private mainOperator;
    FXSDepositorFraxtal private depositor;
    FxsAccumulatorV2Fraxtal private accumulator;
    ILiquidityGauge private liquidityGauge;

    IFraxtalDelegationRegistry private constant DELEGATION_REGISTRY =
        IFraxtalDelegationRegistry(0x098c837FeF2e146e96ceAF58A10F68Fc6326DC4C);
    //IFraxtalDelegationRegistry(Frax.DELEGATION_REGISTRY);
    address private constant INITIAL_DELEGATE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address private constant FRAXTAL_BRIDGE = 0x4200000000000000000000000000000000000010;
    address private constant DAO_FEE_REC = address(0xABFD);
    address private constant LIQUIDITY_FEE_REC = address(0xABBD);
    address private constant GOVERNANCE = address(0xBAAB);

    uint256 private constant amount = 100e18;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        _sdToken = new sdFXSFraxtal("Stake DAO FXS", "sdFXS", address(DELEGATION_REGISTRY), INITIAL_DELEGATE);

        mainOperator = new sdTokenOperatorFraxtal(
            address(_sdToken), GOVERNANCE, FXS.SDTOKEN, FRAXTAL_BRIDGE, address(DELEGATION_REGISTRY), INITIAL_DELEGATE
        );

        liquidityGauge = ILiquidityGauge(
            Utils.deployBytecode(
                Constants.LGV4_NATIVE_FRAXTAL_BYTECODE,
                abi.encode(address(_sdToken), address(this), address(DELEGATION_REGISTRY), INITIAL_DELEGATE)
            )
        );

        locker = new FxsLockerFraxtal(
            GOVERNANCE, address(token), address(veToken), address(DELEGATION_REGISTRY), INITIAL_DELEGATE
        );

        depositor = new FXSDepositorFraxtal(
            address(token),
            address(locker),
            address(_sdToken),
            address(liquidityGauge),
            address(mainOperator),
            address(DELEGATION_REGISTRY),
            INITIAL_DELEGATE
        );

        accumulator = new FxsAccumulatorV2Fraxtal(
            address(liquidityGauge),
            address(locker),
            DAO_FEE_REC,
            LIQUIDITY_FEE_REC,
            GOVERNANCE,
            address(DELEGATION_REGISTRY),
            INITIAL_DELEGATE
        );

        // check if delegation has set correctly during the deploy
        // sdFXS
        assertEq(DELEGATION_REGISTRY.delegationsOf(address(_sdToken)), INITIAL_DELEGATE);
        assertFalse(DELEGATION_REGISTRY.delegationManagementDisabled(address(_sdToken)));
        assertFalse(DELEGATION_REGISTRY.selfManagingDelegations(address(_sdToken)));

        // LiquidityGauge
        assertEq(DELEGATION_REGISTRY.delegationsOf(address(liquidityGauge)), INITIAL_DELEGATE);
        assertFalse(DELEGATION_REGISTRY.delegationManagementDisabled(address(liquidityGauge)));
        assertFalse(DELEGATION_REGISTRY.selfManagingDelegations(address(liquidityGauge)));

        // Locker
        assertEq(DELEGATION_REGISTRY.delegationsOf(address(locker)), INITIAL_DELEGATE);
        assertFalse(DELEGATION_REGISTRY.delegationManagementDisabled(address(locker)));
        assertFalse(DELEGATION_REGISTRY.selfManagingDelegations(address(locker)));

        // Depositor
        assertEq(DELEGATION_REGISTRY.delegationsOf(address(depositor)), INITIAL_DELEGATE);
        assertFalse(DELEGATION_REGISTRY.delegationManagementDisabled(address(depositor)));
        assertFalse(DELEGATION_REGISTRY.selfManagingDelegations(address(depositor)));

        _sdToken.setOperator(address(mainOperator));
        liquidityGauge.add_reward(address(token), address(accumulator));

        // allow depositor to mint sdToken throught the main operator
        vm.startPrank(GOVERNANCE);
        locker.setAccumulator(address(accumulator));
        locker.setDepositor(address(depositor));
        mainOperator.allowOperator(address(depositor));
        vm.stopPrank();

        deal(address(token), address(this), amount);

        vm.startPrank(address(0xBEEF));
        // Mint FXS.
        deal(address(token), address(0xBEEF), amount);
        IERC20(address(token)).approve(address(depositor), amount);

        depositor.createLock(amount);

        vm.stopPrank();

        // whitelist accumulator to be the veFXS's L1 reward claimer
        vm.prank(IYieldDistributorWhitelist(address(yieldDistributor)).owner());
        IYieldDistributorWhitelist(address(yieldDistributor)).setThirdPartyClaimer(FXS.LOCKER, address(accumulator));
    }

    function test_initialization() public {
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
        assertEq(locker.depositor(), address(depositor));

        assertEq(depositor.minter(), address(mainOperator));
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

    function test_claimRewards() public {
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        assertEq(token.balanceOf(address(depositor)), 0);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(token.balanceOf(address(this)), 0);

        bytes memory checkpointData = abi.encodeWithSignature("checkpoint()", "");
        vm.prank(GOVERNANCE);
        locker.execute(address(yieldDistributor), 0, checkpointData);
        uint256 veCheckpointed = yieldDistributor.userVeFXSCheckpointed(address(locker));
        assertApproxEqRel(veCheckpointed, 200e18 * 4, 5e15);

        skip(1 hours);

        assertEq(token.balanceOf(DAO_FEE_REC), 0);
        assertEq(token.balanceOf(LIQUIDITY_FEE_REC), 0);
        assertEq(token.balanceOf(GOVERNANCE), 0);
        assertEq(token.balanceOf(address(liquidityGauge)), 0);

        address claimer = address(0xCCCC);

        vm.prank(claimer);
        accumulator.claimAndNotifyAll(false, false);

        assertEq(token.balanceOf(address(accumulator)), 0);

        uint256 daoFeeRecBalance = token.balanceOf(DAO_FEE_REC);
        uint256 liqFeeRecBalance = token.balanceOf(LIQUIDITY_FEE_REC);
        uint256 claimerBalance = token.balanceOf(claimer);
        uint256 gaugeBalance = token.balanceOf(address(liquidityGauge));

        uint256 totalClaimed = daoFeeRecBalance + liqFeeRecBalance + claimerBalance + gaugeBalance;

        assertEq(daoFeeRecBalance, totalClaimed * accumulator.daoFee() / accumulator.DENOMINATOR());
        assertEq(liqFeeRecBalance, totalClaimed * accumulator.liquidityFee() / accumulator.DENOMINATOR());
        assertEq(claimerBalance, totalClaimed * accumulator.claimerFee() / accumulator.DENOMINATOR());
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
}
