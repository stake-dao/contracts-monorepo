// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "test/utils/Utils.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

address constant MAV_ETH = MAV.TOKEN;
address constant MAV_BASE = 0x64b88c73A5DfA78D1713fE1b4c69a22d7E0faAa7;
address constant MAV_BNB = 0xd691d9a68C887BDF34DA8c36f63487333ACfD103;

address constant VE_MAV_ETH = Maverick.VEMAV;
address constant VE_MAV_BASE = 0xFcCB5263148fbF11d58433aF6FeeFF0Cc49E0EA5;
address constant VE_MAV_BNB = 0xE6108f1869d37E5076a56168C66A1607EdB10819;

abstract contract MAVLockerIntegrationTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    MAVLocker private locker;
    IVotingEscrowMav private veToken;

    sdToken internal _sdToken;
    MAVDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    uint256 private constant amount = 100e18;

    string private rpcAlias;
    uint256 private forkBlock;

    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    constructor(address _token, address _veToken, string memory _rpcAlias, uint256 _forkBlock) {
        rpcAlias = _rpcAlias;
        token = IERC20(_token);
        veToken = IVotingEscrowMav(_veToken);
        forkBlock = _forkBlock;
    }

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl(rpcAlias), forkBlock);
        vm.selectFork(forkId);
        _sdToken = new sdToken("Stake DAO MAV", "sdMAV");

        address liquidityGaugeImpl;
        if (keccak256(abi.encodePacked(rpcAlias)) == keccak256(abi.encodePacked("ethereum"))) {
            liquidityGaugeImpl = Utils.deployBytecode(
                Constants.LGV4_NATIVE_BYTECODE,
                abi.encode(
                    address(_sdToken),
                    address(this),
                    DAO.SDT,
                    DAO.VESDT,
                    DAO.VESDT_BOOST_PROXY,
                    DAO.LOCKER_SDT_DISTRIBUTOR
                )
            );
        } else {
            liquidityGaugeImpl =
                Utils.deployBytecode(Constants.LGV4_XCHAIN_BYTECODE, abi.encode(address(_sdToken), address(this)));
        }

        liquidityGauge = ILiquidityGauge(liquidityGaugeImpl);

        locker = new MAVLocker(address(this), address(token), address(veToken));
        depositor = new MAVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        // Mint MAV for testing.
        deal(address(token), address(this), amount);

        // Mint MAV to the MAVLocker contract
        deal(address(token), address(this), amount);
        deal(address(token), deployer, amount);

        vm.startPrank(deployer);
        IERC20(token).approve(address(depositor), amount);
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

    function test_depositAndStakeWithoutGauge() public {
        // set gauge to zero address in depositor
        depositor.setGauge(address(0));
        /// Skip 1 seconds to avoid depositing in the same block as locking.
        skip(1);

        (uint256 expectedBalance,) = veToken.previewPoints(200e18, MAX_LOCK_DURATION);

        token.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(_sdToken.balanceOf(address(this)), amount);
        assertEq(token.balanceOf(address(depositor)), 0);
        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
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

contract MAVLockerIntegrationTestEth is MAVLockerIntegrationTest(MAV_ETH, VE_MAV_ETH, "mainnet", 18277719) {}

contract MAVLockerIntegrationTestBase is MAVLockerIntegrationTest(MAV_BASE, VE_MAV_BASE, "base", 4821075) {}

contract MAVLockerIntegrationTestBnb is MAVLockerIntegrationTest(MAV_BNB, VE_MAV_BNB, "bnb", 32311843) {}
