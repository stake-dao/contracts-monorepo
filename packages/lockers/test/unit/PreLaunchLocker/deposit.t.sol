// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {PreLaunchLocker, ILiquidityGaugeV4} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerTest} from "test/unit/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__deposit is PreLaunchLockerTest {
    function test_RevertsIfTheAmountIs0(bool stake) external {
        // it reverts if the amount is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.deposit(0, stake);
    }

    function test_RevertsIfTheStateIsNotIDLE(bool stake)
        external
        _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness
    {
        // it reverts if the state is not IDLE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            lockerHarness._cheat_state(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_DEPOSIT_ACTIVE_OR_CANCELED_LOCKER.selector);

            // call the function
            lockerHarness.deposit(1, stake);
        }
    }

    function test_RevertsIfTheUserHasNoAllowanceForTheToken(
        address caller,
        uint256 amount,
        uint256 allowance,
        bool stake
    ) external {
        // it reverts if the user has no allowance for the token

        vm.assume(caller != address(0));
        vm.assume(allowance > 1);
        amount = bound(amount, 1, allowance - 1);

        // mint the token to the caller
        deal(address(token), caller, amount);

        // expect the revert because the allowance is not enough
        vm.expectRevert();

        // try to deposit the tokens
        vm.prank(caller);
        locker.deposit(amount, stake);
    }

    function test_RevertsIfTheUserDoesNotHaveEnoughBalanceForTheToken(address caller, uint256 amount, bool stake)
        external
    {
        // it reverts if the user does not have enough balance for the token

        vm.assume(caller != address(0));
        amount = bound(amount, 1, type(uint256).max - 1);

        // mint the token to the caller
        deal(address(token), caller, amount);

        // expect the revert because the balance is not enough
        vm.expectRevert();

        // try to deposit more tokens than the caller has
        vm.prank(caller);
        locker.deposit(amount + 1, stake);
    }

    function test_RevertsIfTheReceiverIs0() external {
        // it reverts if the receiver is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.deposit(1, true, address(0));
    }

    function test_GivenTheStakeIsTrue(address caller, uint256 amount) external {
        // 1. it mints sdTokens to the locker
        // 2. it stakes the sdTokens in the gauge for the caller
        // 3. it emits the TokensStaked event

        vm.assume(caller != address(0));
        _assumeUnlabeledAddress(caller);
        amount = bound(amount, 1, type(uint256).max);

        // mint the token to the caller and approve the locker to spend the token
        deal(address(token), caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokensStaked(caller, caller, address(gauge), amount);

        // expect the internal calls to be made
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.mint.selector, address(locker), amount), 1);
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.approve.selector, address(gauge), amount), 1);
        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, caller, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        locker.deposit(amount, true);

        // assert the tokens have been transferred to the locker
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(locker)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(sdToken.balanceOf(address(caller)), 0);
        assertEq(sdToken.balanceOf(address(locker)), 0);
        assertEq(sdToken.balanceOf(address(gauge)), amount);

        // assert the gauge tracks the caller's balance
        assertEq(gauge.balanceOf(address(caller)), amount);
        assertEq(gauge.balanceOf(address(locker)), 0);
    }

    function test_GivenTheStakeIsFalse(address caller, uint256 amount) external {
        // it mints sdTokens to the caller

        vm.assume(caller != address(0));
        _assumeUnlabeledAddress(caller);
        amount = bound(amount, 1, type(uint256).max);

        // mint the token to the caller and approve the locker to spend the token
        deal(address(token), caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.mint.selector, address(caller), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        locker.deposit(amount, false);

        // assert the tokens have been transferred to the locker
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(locker)), amount);

        // 1. assert the sdTokens have been minted to the caller
        assertEq(sdToken.balanceOf(address(caller)), amount);
        assertEq(sdToken.balanceOf(address(locker)), 0);
        assertEq(sdToken.balanceOf(address(gauge)), 0);

        // assert the gauge balances have not changed
        assertEq(gauge.balanceOf(address(caller)), 0);
        assertEq(gauge.balanceOf(address(locker)), 0);
    }

    function test_GivenAReceiverWhenTheStakeIsTrue(address caller, uint256 amount, address receiver) external {
        // 1. it stakes the sdTokens in the gauge for the receiver
        // 2. it emits the TokensStaked event

        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != receiver);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        amount = bound(amount, 1, type(uint256).max);

        // mint the token to the caller and approve the locker to spend the token
        deal(address(token), caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // 3. expect the event to be emitted
        vm.expectEmit();
        emit TokensStaked(caller, receiver, address(gauge), amount);

        // expect the internal calls to be made
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.mint.selector, address(locker), amount), 1);
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.approve.selector, address(gauge), amount), 1);
        vm.expectCall(
            address(gauge), abi.encodeWithSelector(ILiquidityGaugeV4.deposit.selector, amount, receiver, false), 1
        );

        // deposit the tokens
        vm.prank(caller);
        locker.deposit(amount, true, receiver);

        // assert the tokens have been transferred to the locker
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(locker)), amount);

        // 1. assert the sdTokens have been minted and transferred to the gauge
        assertEq(sdToken.balanceOf(address(caller)), 0);
        assertEq(sdToken.balanceOf(address(locker)), 0);
        assertEq(sdToken.balanceOf(address(gauge)), amount);

        // assert the gauge tracks the receiver's balance
        assertEq(gauge.balanceOf(address(receiver)), amount);
        assertEq(gauge.balanceOf(address(caller)), 0);
        assertEq(gauge.balanceOf(address(locker)), 0);
    }

    function test_GivenAReceiverWhenTheStakeIsFalse(address caller, uint256 amount, address receiver) external {
        // it mints sdTokens to the receiver

        vm.assume(caller != address(0));
        vm.assume(receiver != address(0));
        vm.assume(caller != receiver);
        _assumeUnlabeledAddress(caller);
        _assumeUnlabeledAddress(receiver);
        amount = bound(amount, 1, type(uint256).max);

        // mint the token to the caller and approve the locker to spend the token
        deal(address(token), caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // 3. expect the internal calls to be made
        vm.expectCall(address(sdToken), abi.encodeWithSelector(ISdToken.mint.selector, address(receiver), amount), 1);

        // deposit the tokens
        vm.prank(caller);
        locker.deposit(amount, false, receiver);

        // assert the tokens have been transferred to the locker
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(locker)), amount);

        // 1. assert the sdTokens have been minted to the receiver
        assertEq(sdToken.balanceOf(address(caller)), 0);
        assertEq(sdToken.balanceOf(address(locker)), 0);
        assertEq(sdToken.balanceOf(address(receiver)), amount);

        // assert the gauge balances have not changed
        assertEq(gauge.balanceOf(address(caller)), 0);
        assertEq(gauge.balanceOf(address(locker)), 0);
        assertEq(gauge.balanceOf(address(receiver)), 0);
    }

    /// @notice Event emitted each time a user stakes their sdTokens.
    /// @param caller The address who called the function.
    /// @param receiver The address who received the gauge token.
    /// @param gauge The gauge that the sdTokens were staked to.
    /// @param amount The amount of sdTokens staked.
    event TokensStaked(address indexed caller, address indexed receiver, address indexed gauge, uint256 amount);
}
