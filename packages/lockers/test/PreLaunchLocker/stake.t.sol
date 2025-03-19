// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness, ExtendedMockERC20, DepositorMock, GaugeMock} from "./PreLaunchLockerHarness.t.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";

contract PreLaunchLocker__stake is Test {
    using stdStorage for StdStorage;

    address private governance;
    PreLaunchLockerHarness private locker;
    ExtendedMockERC20 private token;
    ExtendedMockERC20 private sdToken;
    DepositorMock private depositor;

    function setUp() public {
        // deploy the token
        token = new ExtendedMockERC20();
        token.initialize("Token", "TOKEN", 18);

        // deploy the locker
        governance = makeAddr("governance");
        vm.prank(governance);
        locker = new PreLaunchLockerHarness(makeAddr("token"));

        // deploy the depositor
        depositor = new DepositorMock(address(token));
        sdToken = ExtendedMockERC20(depositor.minter());

        // manually sets the depositor by cheating the slot
        stdstore.target(address(locker)).sig("depositor()").checked_write(address(depositor));

        // manually sets the sdToken by cheating the slot
        stdstore.target(address(locker)).sig("sdToken()").checked_write(address(sdToken));

        vm.label(address(locker), "locker");
        vm.label(address(depositor), "depositor");
        vm.label(address(sdToken), "sdToken");
        vm.label(governance, "governance");
    }

    function test_RevertsIfTheAmountIs0() external {
        // it reverts if the ount is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        locker.stake(0);
    }

    function test_RevertsIfTheStateIsNotACTIVE() external {
        // it reverts if the state is not ACTIVE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.IDLE, PreLaunchLocker.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            locker._cheat_setState(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_STAKE_IDLE_OR_CANCELED_LOCKER.selector);

            // call the function
            locker.stake(1);
        }
    }

    function test_RevertsIfAmountIsGreaterThanTheBalanceOfTheUser(address caller, uint256 amount) external {
        // it reverts if amount is greater than the balance of the user

        vm.assume(caller != address(0));
        amount = bound(amount, 1, type(uint256).max - 1);

        // manually set the balance of the user
        locker._cheat_balances(caller, amount);
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        // expect the revert
        vm.expectRevert(PreLaunchLocker.INSUFFICIENT_BALANCE.selector);

        // call the function
        locker.stake(amount + 1);
    }

    function test_DecreasesTheBalanceOfTheUser(address caller, uint256 balance, uint256 amount) external {
        // it decreases the balance of the user

        vm.assume(caller != address(0));
        balance = bound(balance, 2, type(uint256).max - 1);
        amount = bound(amount, 1, balance - 1);

        // manually set the balance of the user
        locker._cheat_balances(caller, balance);
        // mint the corresponding sdToken to the locker
        sdToken._cheat_mint(address(locker), balance);
        // set the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        // call the function
        vm.prank(caller);
        locker.stake(amount);

        // assert the balance of the user has been decreased
        assertEq(locker.balances(caller), balance - amount);
    }

    function test_DepositsTheAmountInTheGauge(address caller, uint256 balance) external {
        // it deposits the amount in the gauge

        vm.assume(caller != address(0));
        balance = bound(balance, 2, type(uint256).max - 1);

        // manually set the balance of the user
        locker._cheat_balances(caller, balance);
        // mint the corresponding sdToken to the locker
        sdToken._cheat_mint(address(locker), balance);
        // set the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        vm.expectCall(depositor.gauge(), abi.encodeCall(GaugeMock.deposit, (balance, caller)));

        // call the function
        vm.prank(caller);
        locker.stake(balance);
    }

    function test_EmitsTheStakedEvent(address caller, uint256 balance) external {
        // it emits the Staked event

        vm.assume(caller != address(0));
        balance = bound(balance, 2, type(uint256).max - 1);

        // manually set the balance of the user
        locker._cheat_balances(caller, balance);
        // mint the corresponding sdToken to the locker
        sdToken._cheat_mint(address(locker), balance);
        // set the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        vm.expectEmit(true, true, true, true);
        emit TokensStaked(caller, depositor.gauge(), balance);

        // call the function
        vm.prank(caller);
        locker.stake(balance);
    }

    function test_StakesTheMaximumAmountGivenNoAmount(address caller, uint256 balance) external {
        // it stakes the maximum amount given no amount

        vm.assume(caller != address(0));
        balance = bound(balance, 2, type(uint256).max - 1);

        // manually set the balance of the user
        locker._cheat_balances(caller, balance);
        // mint the corresponding sdToken to the locker
        sdToken._cheat_mint(address(locker), balance);
        // set the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        // call the function
        vm.prank(caller);
        locker.stake(); // no amount is given

        // assert the entire balance has been staked
        assertEq(locker.balances(caller), 0);
    }

    event TokensStaked(address indexed account, address gauge, uint256 amount);
}
