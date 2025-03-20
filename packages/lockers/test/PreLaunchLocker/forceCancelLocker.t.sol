// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerTest} from "test/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__forceCancelLocker is PreLaunchLockerTest {
    function test_RevertsIfTheStateIsNotIDLE() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it reverts if the state is not IDLE

        // manually force the state to ACTIVE and expect a revert
        lockerHarness._cheat_state(PreLaunchLocker.STATE.ACTIVE);
        vm.expectRevert(PreLaunchLocker.CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);
        lockerHarness.forceCancelLocker();

        // manually force the state to CANCELED and expect a revert
        lockerHarness._cheat_state(PreLaunchLocker.STATE.CANCELED);
        vm.expectRevert(PreLaunchLocker.CANNOT_FORCE_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);
        lockerHarness.forceCancelLocker();
    }

    function test_RevertsIfTheDelayIsNotPassed() external {
        // it reverts if the delay is not passed

        // fast forward the timestamp by 1 second less than the delay and expect a revert
        vm.warp(block.timestamp + locker.FORCE_CANCEL_DELAY() - 1);
        vm.expectRevert(PreLaunchLocker.CANNOT_FORCE_CANCEL_RECENTLY_CREATED_LOCKER.selector);
        locker.forceCancelLocker();
    }

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        // fast forward the timestamp by the delay and expect the state to be CANCELED
        vm.warp(block.timestamp + locker.FORCE_CANCEL_DELAY());
        locker.forceCancelLocker();
        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.CANCELED));
    }
}
