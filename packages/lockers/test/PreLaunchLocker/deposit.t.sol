// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";

contract PreLaunchLocker__deposit is Test {
    PreLaunchLockerHarness private locker;
    ExtendedMockERC20 private token;

    function setUp() public {
        token = new ExtendedMockERC20();
        token.initialize("Token", "TKN", 18);

        locker = new PreLaunchLockerHarness(address(token));
    }

    function test_RevertsIfTheAmountIs0() external {
        // it reverts if the amount is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.deposit(0);
    }

    function test_RevertsIfTheStateIsNotIDLE() external {
        // it reverts if the state is not IDLE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            locker._cheat_setState(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_DEPOSIT_ACTIVE_OR_CANCELED_LOCKER.selector);

            // call the function
            locker.deposit(1);
        }
    }

    function test_RevertsIfTheUserHasNoAllowanceForTheToken(address caller, uint256 amount) external {
        // it reverts if the user has no allowance for the token

        vm.assume(caller != address(0));
        vm.assume(amount > 0);

        // mint the token to the caller
        token._cheat_mint(caller, amount);

        // expect the revert
        vm.expectRevert();

        // deposit the token
        vm.prank(caller);
        locker.deposit(amount);
    }

    function test_RevertsIfTheUserDoesNotHaveEnoughBalanceForTheToken(address caller, uint256 amount) external {
        // it reverts if the user does not have enough balance for the token

        vm.assume(caller != address(0));
        amount = bound(amount, 1, type(uint256).max - 1);

        // mint the token to the caller & approve the locker to spend the token
        token._cheat_mint(caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // expect the revert
        vm.expectRevert();

        // deposit the token
        vm.prank(caller);
        locker.deposit(amount + 1);
    }

    function test_IncreasesTheBalanceOfTheUser(address caller, uint256 amount) external {
        // it increases the balance of the user

        vm.assume(caller != address(0));
        vm.assume(amount > 0);

        // assert the balances are 0
        assertEq(locker.balances(caller), 0);
        assertEq(token.balanceOf(address(locker)), 0);

        // mint the token to the caller & approve the locker to spend the token
        token._cheat_mint(caller, amount);
        vm.prank(caller);
        token.approve(address(locker), amount);

        // deposit the token
        vm.prank(caller);
        locker.deposit(amount);

        // assert the balances have been updated correctly
        assertEq(token.balanceOf(address(locker)), amount);
        assertEq(locker.balances(caller), amount);
    }
}

contract ExtendedMockERC20 is MockERC20 {
    function _cheat_mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
