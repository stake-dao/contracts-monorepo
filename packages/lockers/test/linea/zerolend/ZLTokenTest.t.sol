// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {BaseZeroLendTokenTest} from "test/linea/zerolend/common/BaseZeroLendTokenTest.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/ISdZeroLocker.sol";
import {IZeroBaseLocker} from "src/common/interfaces/zerolend/IZeroBaseLocker.sol";

// end to end tests for the ZeroLend integration
contract ZeroLendTest is BaseZeroLendTokenTest {
    constructor() {}

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("linea"), 14_369_758);
        vm.selectFork(forkId);
        _deployZeroIntegration();
    }

    function _depositTokens() public {
        zeroToken.approve(address(depositor), 1 ether);
        depositor.deposit(1 ether, true, false, address(this));
    }

    function test_canDepositTokens() public {
        assertEq(zeroToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens();

        // validate that sdZero was minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 1 ether);
    }

    function _claimRewards() public {
        accumulator.claimAndNotifyAll(false, false);
    }

    function test_canClaimRewards() public {
        _depositTokens();

        skip(3600 * 24 * 30);

        _claimRewards();

        assertEq(zeroToken.balanceOf(address(liquidityGauge)) > 0, true);

        // TODO make the math to test that the amount received by the gauge is exactly what was expected
    }

    // TODO can claim WETH as well if added when claiming

    // TODO
    // function test_canClaimRewardsFromGauge() public {}

    // TODO test with multiple stakers

    // TODO test where withdraw tokens

    // TODO test that can deposit without staking sdZERO

    // TODO test that can deposit to a different address

    // TODO test that can deposit to a different address without staking sdZERO

    function test_canReleaseLockedTokensAfterLockEnds() public {
        _depositTokens();

        uint256 endLockTimestamp =
            IZeroBaseLocker(address(zeroLockerToken)).locked(ISdZeroLocker(locker).lockerTokenId()).end;
        uint256 lockerTokenId = ISdZeroLocker(locker).lockerTokenId();
        uint256 zeroLockedAmount =
            IZeroBaseLocker(address(zeroLockerToken)).locked(ISdZeroLocker(locker).lockerTokenId()).amount;

        // fast forward 1s before locking should end
        vm.warp(endLockTimestamp - 1);

        // can't be done before the lock ends
        vm.prank(ILocker(locker).governance());
        vm.expectRevert("The lock didn't expire");
        ISdZeroLocker(locker).release(address(1), lockerTokenId);

        // fast forward to 4 years after locking
        vm.warp(endLockTimestamp);

        // can't be done right after if not governance
        vm.expectRevert(ILocker.GOVERNANCE.selector);
        ISdZeroLocker(locker).release(address(1), lockerTokenId);

        // can be done right after by governance
        vm.prank(ILocker(locker).governance());
        ISdZeroLocker(locker).release(address(1), lockerTokenId);

        // the right amount of tokens is withdrawn
        assertEq(zeroToken.balanceOf(address(1)), zeroLockedAmount);
    }

    // TODO test rescue of locker NFT sent to the locker by random user
}
