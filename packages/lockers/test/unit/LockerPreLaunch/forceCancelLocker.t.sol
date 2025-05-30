// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {PreLaunchLockerTest} from "test/unit/LockerPreLaunch/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__forceCancelLocker is PreLaunchLockerTest {
    function test_RevertsIfTheStateIsNotIDLE() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it reverts if the state is not IDLE

        // manually force the state to ACTIVE and expect a revert
        lockerHarness._cheat_state(LockerPreLaunch.STATE.ACTIVE);
        vm.expectRevert(LockerPreLaunch.CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);
        lockerHarness.forceCancelLocker();

        // manually force the state to CANCELED and expect a revert
        lockerHarness._cheat_state(LockerPreLaunch.STATE.CANCELED);
        vm.expectRevert(LockerPreLaunch.CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);
        lockerHarness.forceCancelLocker();
    }

    function test_RevertsIfTheDelayIsNotPassed() external {
        // it reverts if the delay is not passed

        // fast forward the timestamp by 1 second less than the delay and expect a revert
        vm.warp(block.timestamp + locker.FORCE_CANCEL_DELAY() - 1);
        vm.expectRevert(LockerPreLaunch.CANNOT_FORCE_CANCEL_RECENTLY_CREATED_LOCKER.selector);
        locker.forceCancelLocker();
    }

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        // fast forward the timestamp by the delay and expect the state to be CANCELED
        vm.warp(block.timestamp + locker.FORCE_CANCEL_DELAY());
        locker.forceCancelLocker();
        assertEq(uint256(locker.state()), uint256(LockerPreLaunch.STATE.CANCELED));
    }
}
