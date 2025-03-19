// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness, ExtendedMockERC20, DepositorMock} from "./PreLaunchLockerHarness.t.sol";

contract PreLaunchLocker__lock is Test {
    PreLaunchLockerHarness private locker;
    address private governance;

    ExtendedMockERC20 private token;

    function setUp() public {
        // deploy the token
        token = new ExtendedMockERC20();
        token.initialize("Token", "TOKEN", 18);

        // deploy the locker
        governance = makeAddr("governance");
        vm.prank(governance);
        locker = new PreLaunchLockerHarness(address(token));
    }

    // deploy the mock version of the depositor
    function _deployDepositor() internal returns (address) {
        return address(new DepositorMock(address(token)));
    }

    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(PreLaunchLocker.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.lock(makeAddr("depositor"));
    }

    function test_RevertsIfTheDepositorIs0() external {
        // it reverts if the depositor is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        vm.prank(governance);
        locker.lock(address(0));
    }

    function test_RevertsIfTheTokenAssociatedWithTheDepositorIsNotTheSame() external {
        // it reverts if the token associated with the depositor is not the same
    }

    function test_RevertsIfTheStateIsNotIDLE() external {
        // it reverts if the state is not IDLE

        address depositor = _deployDepositor();

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];
        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            locker._cheat_setState(states[i]);

            // try to lock the locker
            vm.expectRevert(PreLaunchLocker.CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER.selector);
            vm.prank(governance);
            locker.lock(depositor);
        }
    }

    function test_RevertsIfTheirIsNothingToLock() external {
        // it reverts if their is nothing to lock

        address depositor = _deployDepositor();

        // mock the balance of the locker to be 0
        vm.mockCall(address(token), abi.encodeWithSelector(token.balanceOf.selector, address(locker)), abi.encode(0));

        // expect the revert when trying to lock the locker
        vm.expectRevert(PreLaunchLocker.NOTHING_TO_LOCK.selector);
        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_SetsTheDepositorToTheGivenValue() external {
        // it sets the depositor to the given value

        address depositor = _deployDepositor();

        // mint the token to the locker
        token._cheat_mint(address(locker), 1000);

        // lock the locker
        vm.prank(governance);
        locker.lock(depositor);

        // assert the depositor is set correctly
        assertEq(address(locker.depositor()), depositor);
    }

    function test_SetsTheSdTokenToTheValueFetchedFromTheDepositor() external {
        // it sets the sdToken to the value fetched from the depositor

        address depositor = _deployDepositor();

        // mint the token to the locker
        token._cheat_mint(address(locker), 1000);

        // lock the locker
        vm.prank(governance);
        locker.lock(depositor);

        // assert the sdToken is set correctly
        assertEq(address(locker.sdToken()), DepositorMock(depositor).minter());
    }

    function test_LockTheBalanceOfTokenToTheDepositorAndReceiveTheEquivalentAmountOfSdToken() external {
        // it lock the balance of token to the depositor and receive the equivalent amount of sdToken

        address depositor = _deployDepositor();
        address sdToken = DepositorMock(depositor).minter();

        // mint the token to the locker
        token._cheat_mint(address(locker), 1000);

        // lock the locker
        vm.prank(governance);
        locker.lock(depositor);

        // assert the tokens held by the locker have been converted to sdToken
        assertEq(ExtendedMockERC20(token).balanceOf(address(locker)), 0);
        assertEq(ExtendedMockERC20(sdToken).balanceOf(address(locker)), 1000);

        // assert the depositor now holds the initial token balance
        assertEq(ExtendedMockERC20(sdToken).balanceOf(depositor), 0);
        assertEq(ExtendedMockERC20(token).balanceOf(depositor), 1000);
    }

    function test_RevertsIfTheAmountOfSdTokenIsNotTheSameAsTheAmountOfTokenLocked() external {
        // it reverts if the amount of sdToken is not the same as the amount of token locked

        address depositor = _deployDepositor();
        address sdToken = DepositorMock(depositor).minter();

        // mint the token to the locker
        token._cheat_mint(address(locker), 1000);

        // block the minting of the sdToken normally made by the depositor to the locker
        vm.mockCall(
            sdToken,
            abi.encodeWithSelector(ExtendedMockERC20._cheat_mint.selector, address(locker), 1000),
            abi.encode(1)
        );

        // expect the revert because the correct amount of sdToken was not minted
        vm.expectRevert(PreLaunchLocker.SD_TOKEN_NOT_MINTED.selector);
        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_SetsTheStateToACTIVE() external {
        // it sets the state to ACTIVE

        address depositor = _deployDepositor();

        // mint the token to the locker
        token._cheat_mint(address(locker), 1000);

        // lock the locker
        vm.prank(governance);
        locker.lock(depositor);

        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.ACTIVE));
    }
}
