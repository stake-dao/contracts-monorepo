// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchBaseDepositor} from "src/common/depositor/PreLaunchBaseDepositor.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerTest} from "test/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__lock is PreLaunchLockerTest {
    address internal depositor;
    address internal postPreLaunchLocker;

    function setUp() public override {
        super.setUp();

        // deploy the locker that will be used once all the protocol is deployed (after the pre-launch period)
        postPreLaunchLocker = address(new LockerMock());

        // deploy the depositor
        depositor = address(
            new PreLaunchBaseDepositor(
                address(token), postPreLaunchLocker, address(sdToken), address(gauge), 1_000, address(locker)
            )
        );
    }

    function test_RevertIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(PreLaunchLocker.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.lock(depositor);
    }

    function test_RevertIfTheDepositorIs0() external {
        // it reverts if the depositor is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        vm.prank(governance);
        locker.lock(address(0));
    }

    function test_RevertIfTheStateIsNotIDLE() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it reverts if the state is not IDLE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];
        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            lockerHarness._cheat_state(states[i]);

            // try to lock the locker
            vm.expectRevert(PreLaunchLocker.CANNOT_LOCK_ACTIVE_OR_CANCELED_LOCKER.selector);
            vm.prank(governance);
            lockerHarness.lock(depositor);
        }
    }

    function test_RevertIfTheTokenAssociatedWithTheDepositorIsNotTheExpectedOne(address incorrectToken) external {
        // it revert if the token associated with the depositor is not the expected one

        vm.assume(incorrectToken != address(token));

        vm.mockCall(address(depositor), bytes4(keccak256("token()")), abi.encode(incorrectToken));
        vm.expectRevert(PreLaunchLocker.INVALID_TOKEN.selector);

        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_RevertIfTheGaugeAssociatedWithTheDepositorIsNotTheExpectedOne(address incorrectGauge) external {
        // it revert if the gauge associated with the depositor is not the expected one

        vm.assume(incorrectGauge != address(gauge));

        vm.mockCall(address(depositor), bytes4(keccak256("gauge()")), abi.encode(incorrectGauge));
        vm.expectRevert(PreLaunchLocker.INVALID_GAUGE.selector);

        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_RevertIfTheSdTokenAssociatedWithTheDepositorIsNotTheExpectedOne(address incorrectSdToken) external {
        // it revert if the sdToken associated with the depositor is not the expected one

        vm.assume(incorrectSdToken != address(sdToken));

        vm.mockCall(address(depositor), bytes4(keccak256("minter()")), abi.encode(incorrectSdToken));
        vm.expectRevert(PreLaunchLocker.INVALID_SD_TOKEN.selector);

        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_RevertsIfTheirIsNothingToLock() external {
        // it reverts if their is nothing to lock

        // make sure the locker has no balance
        deal(address(token), address(locker), 0);

        // expect the revert when trying to lock the locker
        vm.expectRevert(PreLaunchLocker.NOTHING_TO_LOCK.selector);
        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_RevertIfTheAmountOfSdTokenIsNotTheSameAsTheAmountOfTokenLocked() external {
        // it revert if the amount of sdToken is not the same as the amount of token locked

        // give the locker a balance of 100_000
        deal(address(token), address(locker), 100_000);

        // mock the depositor to not mint the sdToken
        vm.mockCall(address(depositor), bytes4(keccak256("createLock(uint256)")), abi.encode(0));

        // expect the revert when trying to lock the locker
        vm.expectRevert(PreLaunchLocker.TOKEN_NOT_TRANSFERRED_TO_LOCKER.selector);
        vm.prank(governance);
        locker.lock(depositor);
    }

    function test_SetsTheDepositorToTheGivenValue(uint256 balance) external {
        // it sets the depositor to the given value

        vm.assume(balance > 0);
        deal(address(token), address(locker), balance);

        // expect the depositor to call the definitive locker
        vm.expectCall(postPreLaunchLocker, abi.encodeWithSelector(LockerMock.createLock.selector), 1);

        vm.prank(governance);
        locker.lock(depositor);

        assertEq(address(locker.depositor()), depositor);
    }

    function test_TransfersTheBalanceOfTokenToTheFinalLocker(uint256 balance) external {
        // it transfers the balance of token to the final locker

        vm.assume(balance > 0);
        deal(address(token), address(locker), balance);

        assertEq(token.balanceOf(address(locker)), balance);

        vm.prank(governance);
        locker.lock(depositor);

        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(postPreLaunchLocker)), balance);
    }

    function test_TransfersTheOperatorPermissionOfTheSdTokenToTheDepositor() external {
        // it transfers the operator permission of the sdToken to the depositor

        deal(address(token), address(locker), 10);

        assertEq(sdToken.operator(), address(locker));

        vm.prank(governance);
        locker.lock(depositor);

        assertEq(sdToken.operator(), address(depositor));
    }

    function test_SetsTheStateToACTIVE() external {
        // it sets the state to ACTIVE
        deal(address(token), address(locker), 10);

        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.IDLE));

        vm.prank(governance);
        locker.lock(depositor);

        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.ACTIVE));
    }
}

contract LockerMock {
    function createLock(uint256 amount, uint256 unlockTime) external {}
}
