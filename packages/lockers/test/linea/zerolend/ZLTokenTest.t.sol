// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {BaseZeroLendTokenTest} from "test/linea/zerolend/common/BaseZeroLendTokenTest.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/stakedao/ISdZeroLocker.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

// end to end tests for the ZeroLend integration
contract ZeroLendTest is BaseZeroLendTokenTest {
    constructor() {}

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("linea"), 14_369_758);
        vm.selectFork(forkId);
        _deployZeroIntegration();
    }

    function _depositTokens(bool _lock, bool _stake, address _user) public {
        zeroToken.approve(address(depositor), 1 ether);
        depositor.deposit(1 ether, _lock, _stake, _user);

        // Offset the creating vs the actual test
        vm.warp(block.timestamp + 30 days);
    }

    function test_canDeploySafeProxy() public {}

    function test_canDepositTokensWithoutStaking() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens(true, false, address(this));

        // check that sdZero was minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 1 ether);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
    }

    function test_canDepositTokensAndStake() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens(true, true, address(this));

        // check that gauge sdZero was minted and not sdZero
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), 1 ether);
    }

    function test_canDepositToDifferentAddressWithoutStaking() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens(true, false, address(5));

        // check that gauge sdZero was minted and not sdZero
        assertEq(ISdToken(sdToken).balanceOf(address(5)), 1 ether);
        assertEq(liquidityGauge.balanceOf(address(5)), 0);
    }

    function test_canDepositToDifferentAddressAndStake() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens(true, true, address(5));

        // check that gauge sdZero was minted and not sdZero
        assertEq(ISdToken(sdToken).balanceOf(address(5)), 0);
        assertEq(liquidityGauge.balanceOf(address(5)), 1 ether);
    }

    function test_cantDepositZeroTokens() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        zeroToken.approve(address(depositor), 1 ether);

        vm.expectRevert(IDepositor.AMOUNT_ZERO.selector);
        depositor.deposit(0, true, true, address(0));
    }

    function test_cantDepositToZeroAddress() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        zeroToken.approve(address(depositor), 1 ether);

        vm.expectRevert(IDepositor.ADDRESS_ZERO.selector);
        depositor.deposit(1 ether, true, true, address(0));
    }

    function _claimRewards() public {
        accumulator.claimAndNotifyAll(false, false);
    }

    function test_canClaimRewards() public {
        _depositTokens(true, true, address(this));

        uint256 oneMonth = 3600 * 24 * 30;
        skip(oneMonth);

        uint256 balanceBefore = zeroToken.balanceOf(address(liquidityGauge));
        uint256 earned = IZeroVp(address(veZero)).earned(address(locker));

        _claimRewards();

        assertEq(
            zeroToken.balanceOf(address(liquidityGauge)) - balanceBefore,
            earned
            // treasury fee
            - earned * 1e17 / 1e18
            // SD fee
            - earned * 5e16 / 1e18
            // claim fee
            - earned * 1e15 / 1e18
        );
    }

    // TODO need to reactivate this test as it doesn't work anymore since we only take the actual
    // reward instead of the whole locker's balance. The only way to do it is to modify the ZEROvp
    // contract to make it send WETH.

    // // fake the adding of WETH as reward, make sure it gets claimed
    // function test_canClaimWethRewards() public {
    //     _depositTokens(true, true, address(this));

    //     skip(3600 * 24 * 30);

    //     // manually give 1 WETH to the locker
    //     deal(address(WETH), address(locker), 1 ether);
    //     _claimRewards();

    //     // make sure it gets sent to the gauge
    //     assertEq(WETH.balanceOf(address(liquidityGauge)), 1 ether);
    // }

    // TODO need to reactivate weth test as it doesn't work anymore since we only take the actual
    // reward instead of the whole locker's balance. The only way to do it is to modify the ZEROvp
    // contract to make it send WETH.

    function test_canClaimRewardsFromGauge() public {
        _depositTokens(true, true, address(this));

        skip(3600 * 24 * 30);

        // // manually give 1 WETH to the locker
        // deal(address(WETH), address(locker), 1 ether);
        _claimRewards();

        // go to the end of the reward distribution period of the gauge
        skip(3600 * 24 * 7);

        deal(address(zeroToken), address(this), 0);
        assertEq(zeroToken.balanceOf(address(this)), 0);
        assertEq(IERC20(sdToken).balanceOf(address(this)), 0);
        assertEq(liquidityGauge.balanceOf(address(this)), 1 ether);

        liquidityGauge.claim_rewards();

        // make sure user got the reward
        assertEq(zeroToken.balanceOf(address(this)) > 0, true);

        // there are some rounding
        // assertEq(WETH.balanceOf(address(this)) > 0.9999 ether, true);
    }

    function test_multipleStakers() public {
        address zeroLendTokenHolder1 = 0x4c11F940E2D09eF9D5000668c1C9410f0AaF0833;
        address zeroLendTokenHolder2 = 0xf18601650f927584a9785d24f1a4D9CfEeba19FA;

        assertEq(zeroToken.balanceOf(zeroLendTokenHolder1) > 1 ether, true);
        assertEq(zeroToken.balanceOf(zeroLendTokenHolder2) > 1 ether, true);

        vm.startPrank(zeroLendTokenHolder1);
        _depositTokens(true, true, zeroLendTokenHolder1);
        vm.stopPrank();

        // warp 6 months
        vm.warp(block.timestamp + 6 * 30 * 24 * 3600);

        vm.startPrank(zeroLendTokenHolder2);
        _depositTokens(true, true, zeroLendTokenHolder2);
        vm.stopPrank();

        // check that sdZero was minted
        assertEq(liquidityGauge.balanceOf(zeroLendTokenHolder1), 1 ether);
        assertEq(liquidityGauge.balanceOf(zeroLendTokenHolder2), 1 ether);

        skip(3600 * 24 * 30);
        _claimRewards();

        uint256 zeroTokenBalance1BeforeClaim = zeroToken.balanceOf(zeroLendTokenHolder1);
        uint256 zeroTokenBalance2BeforeClaim = zeroToken.balanceOf(zeroLendTokenHolder2);

        skip(3600 * 24 * 7);
        vm.prank(zeroLendTokenHolder1);
        liquidityGauge.claim_rewards();
        vm.prank(zeroLendTokenHolder2);
        liquidityGauge.claim_rewards();

        // make sure users got the rewards
        assertEq(zeroToken.balanceOf(zeroLendTokenHolder1) > zeroTokenBalance1BeforeClaim, true);
        assertEq(zeroToken.balanceOf(zeroLendTokenHolder2) > zeroTokenBalance2BeforeClaim, true);
    }

    function test_canWithdrawTokens() public {
        _depositTokens(true, true, address(this));

        skip(3600 * 24 * 30);

        _claimRewards();

        assertEq(zeroToken.balanceOf(address(liquidityGauge)) > 0, true);

        uint256 gaugeAmount = liquidityGauge.balanceOf(address(this));

        liquidityGauge.withdraw(gaugeAmount, false);

        assertEq(IERC20(sdToken).balanceOf(address(this)), gaugeAmount);
    }

    function test_canReleaseLockedTokensAfterLockEnds() public {
        // TODO reactivate

        // _depositTokens(true, true, address(this));

        // console.log("here1");

        // uint256 endLockTimestamp =
        //     ILockerToken(address(zeroLockerToken)).locked(ISdZeroLocker(locker).zeroLockedTokenId()).end;
        // uint256 zeroLockedAmount =
        //     ILockerToken(address(zeroLockerToken)).locked(ISdZeroLocker(locker).zeroLockedTokenId()).amount;

        // // fast forward 1s before locking should end
        // vm.warp(endLockTimestamp - 1);

        // console.log("here2");

        // // can't be done before the lock ends
        // vm.prank(ILocker(locker).governance());
        // vm.expectRevert("The lock didn't expire");
        // ISdZeroLocker(locker).release(address(1));

        // // fast forward to 4 years after locking
        // vm.warp(endLockTimestamp);
        // console.log("here3");

        // // can't be done right after if not governance
        // vm.expectRevert(ILocker.GOVERNANCE.selector);
        // ISdZeroLocker(locker).release(address(1));

        // // can be done right after by governance
        // vm.prank(ILocker(locker).governance());
        // ISdZeroLocker(locker).release(address(1));

        // console.log("here4");
        // // the right amount of tokens is withdrawn
        // assertEq(zeroToken.balanceOf(address(1)), zeroLockedAmount);
    }
}
