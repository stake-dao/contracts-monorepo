// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/PreLaunchLocker.sol";
import {PreLaunchLockerHarness, ExtendedMockERC20} from "./PreLaunchLockerHarness.t.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";

contract PreLaunchLocker__withdraw is Test {
    using stdStorage for StdStorage;

    ExtendedMockERC20 private token;
    PreLaunchLockerHarness private locker;

    function setUp() public {
        token = new ExtendedMockERC20();

        locker = new PreLaunchLockerHarness(address(token));
    }

    function _cheat_balances(address caller, uint256 balance) internal {
        // manually set the balance of the user
        locker._cheat_balances(caller, balance);
        // mint the corresponding sdToken to the locker
        token._cheat_mint(address(locker), balance);
    }

    function _cheat_balances(uint256 balance) internal {
        _cheat_balances(address(this), balance);
    }

    function test_RevertsIfTheAmountIs0() external {
        // it reverts if the amount is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.withdraw(0);
    }

    function test_RevertsIfAmountIsGreaterThanTheBalanceOfTheUser(uint256 balance) external {
        // it reverts if amount is greater than the balance of the user

        balance = bound(balance, 2, type(uint256).max - 1);
        _cheat_balances(balance - 1);

        vm.expectRevert(PreLaunchLocker.INSUFFICIENT_BALANCE.selector);
        locker.withdraw(balance);
    }

    function test_RevertsIfTheStateIsIDLE(uint256 balance) external {
        // it reverts if the state is IDLE

        vm.assume(balance > 0);
        _cheat_balances(balance);

        vm.expectRevert(PreLaunchLocker.CANNOT_WITHDRAW_IDLE_LOCKER.selector);
        locker.withdraw(balance);
    }

    function test_DecreasesTheBalanceOfTheUser(uint256 balance, uint256 amount) external {
        // it decreases the balance of the user

        balance = bound(balance, 2, type(uint256).max - 1);
        amount = bound(amount, 1, balance - 1);

        _cheat_balances(balance);

        locker._cheat_setState(PreLaunchLocker.STATE.CANCELED);
        locker.withdraw(amount);
        assertEq(locker.balances(address(this)), balance - amount);
    }

    function test_WhenTheStateIsACTIVE(uint256 balance, uint256 amount) external {
        // it transfer the sdToken to the user

        balance = bound(balance, 2, type(uint256).max - 1);
        amount = bound(amount, 1, balance - 1);

        // deploy the sdToken and store the address of the sdToken in the locker
        ExtendedMockERC20 sdToken = new ExtendedMockERC20();
        stdstore.target(address(locker)).sig("sdToken()").checked_write(address(sdToken));

        // manually set the balance of the user and mint the corresponding sdToken to the locker
        _cheat_balances(balance);
        sdToken._cheat_mint(address(locker), balance);

        // manually set the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        locker.withdraw(amount);
        assertEq(sdToken.balanceOf(address(locker)), balance - amount);
        assertEq(sdToken.balanceOf(address(this)), amount);
    }

    function test_WhenTheStateIsCANCELED(uint256 balance, uint256 amount) external {
        // it transfer the token to the user

        balance = bound(balance, 2, type(uint256).max - 1);
        amount = bound(amount, 1, balance - 1);

        _cheat_balances(balance);
        locker._cheat_setState(PreLaunchLocker.STATE.CANCELED);

        assertEq(token.balanceOf(address(this)), 0);

        locker.withdraw(amount);

        assertEq(token.balanceOf(address(locker)), balance - amount);
        assertEq(token.balanceOf(address(this)), amount);
    }

    function test_WithdrawsTheMaximumAmountGivenNoAmount(uint256 balance) external {
        // it withdraws the maximum amount given no amount

        balance = bound(balance, 2, type(uint256).max - 1);

        _cheat_balances(balance);
        locker._cheat_setState(PreLaunchLocker.STATE.CANCELED);

        locker.withdraw(); // no amount is given

        // assert the balance of the user is 0 because everything has been withdrawn
        assertEq(locker.balances(address(this)), 0);
    }
}
