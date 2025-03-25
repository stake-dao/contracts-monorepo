// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerTest} from "test/unit/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__withdraw is PreLaunchLockerTest {
    function test_RevertsIfTheAmountIs0(bool staked) external {
        // it reverts if the amount is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.withdraw(0, staked);
    }

    function test_RevertIfTheStateIsNotCANCELED(bool staked)
        external
        _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness
    {
        // it revert if the state is not CANCELED

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.IDLE];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            lockerHarness._cheat_state(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_WITHDRAW_IDLE_OR_ACTIVE_LOCKER.selector);

            // call the function
            lockerHarness.withdraw(1, staked);
        }
    }

    function test_RevertIfTheCallerDidntApproveTheGaugeTokenWhenTheStakeIsTrue(
        address caller,
        uint256 balance,
        uint256 amount
    ) external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it revert if the caller didn't approve the gauge token when the stake is true

        vm.assume(caller != address(0));
        _assumeUnlabeledAddress(caller);

        balance = bound(balance, 2, type(uint256).max);
        amount = bound(amount, 1, balance - 1);

        // mint the total balance to the locker
        deal(address(token), address(locker), balance);

        // mint the amount the caller is expected to have
        deal(address(sdToken), caller, amount);

        // approve less than the amount the caller is going to withdraw
        vm.prank(caller);
        sdToken.approve(address(locker), amount - 1);

        // manually set the state to CANCELED
        lockerHarness._cheat_state(PreLaunchLocker.STATE.CANCELED);

        vm.expectRevert();
        vm.prank(caller);
        lockerHarness.withdraw(amount, true);
    }

    function test_GivenTheStakeIsTrue(address caller, uint256 balance, uint256 amount)
        external
        _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness
    {
        // it transfers caller gauge token and burn the associated sdToken
        // it transfers back the default token to the caller

        vm.assume(caller != address(0));
        _assumeUnlabeledAddress(caller);

        balance = bound(balance, 2, type(uint256).max);
        amount = bound(amount, 1, balance - 1);

        // manually set the state to CANCELED
        lockerHarness._cheat_state(PreLaunchLocker.STATE.CANCELED);

        // set the expected amount of gauge tokens the caller is expected to have
        deal(address(sdToken), address(caller), amount);
        vm.prank(caller);
        sdToken.approve(address(gauge), amount);
        vm.prank(caller);
        gauge.deposit(amount, caller, false);

        // set the total balance to the locker
        deal(address(token), address(locker), balance);

        // approve the locker to spend the gauge tokens
        vm.prank(caller);
        gauge.approve(address(locker), amount);

        // withdraw the amount
        vm.prank(caller);
        lockerHarness.withdraw(amount, true);

        // verify the balances are correct after the withdrawal
        assertEq(sdToken.balanceOf(caller), 0);
        assertEq(sdToken.balanceOf(address(locker)), 0);

        assertEq(token.balanceOf(caller), amount);
        assertEq(token.balanceOf(address(locker)), balance - amount);

        assertEq(gauge.balanceOf(caller), 0);
        assertEq(gauge.balanceOf(address(locker)), 0);
    }

    function test_GivenTheStakeIsFalse(address caller, uint256 balance, uint256 amount)
        external
        _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness
    {
        // it burn the sdToken held by the caller
        // it transfers back the default token to the caller

        vm.assume(caller != address(0));
        _assumeUnlabeledAddress(caller);

        balance = bound(balance, 2, type(uint256).max);
        amount = bound(amount, 1, balance - 1);

        // mint the total balance to the locker
        deal(address(token), address(locker), balance);

        // mint the amount the caller is expected to have
        deal(address(sdToken), caller, amount);

        // approve the locker to spend the sdToken held by the caller
        vm.prank(caller);
        sdToken.approve(address(locker), amount);

        // verify the initial balances are correct
        assertEq(sdToken.balanceOf(caller), amount);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(address(locker)), balance);

        // manually set the state to CANCELED
        lockerHarness._cheat_state(PreLaunchLocker.STATE.CANCELED);

        // withdraw the amount
        vm.prank(caller);
        lockerHarness.withdraw(amount, false);

        // verify the balances are correct after the withdrawal
        assertEq(sdToken.balanceOf(caller), 0);
        assertEq(token.balanceOf(caller), amount);
        assertEq(token.balanceOf(address(locker)), balance - amount);
        assertEq(sdToken.balanceOf(address(locker)), 0);
    }
}
