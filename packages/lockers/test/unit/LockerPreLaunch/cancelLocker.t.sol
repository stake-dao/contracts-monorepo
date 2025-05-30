// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {PreLaunchLockerTest} from "test/unit/LockerPreLaunch/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__cancelLocker is PreLaunchLockerTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(LockerPreLaunch.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.cancelLocker();
    }

    function test_RevertsIfTheStateIsNotIDLE() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it reverts if the state is not IDLE

        LockerPreLaunch.STATE[2] memory states = [LockerPreLaunch.STATE.ACTIVE, LockerPreLaunch.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            lockerHarness._cheat_state(states[i]);

            // expect the revert
            vm.expectRevert(LockerPreLaunch.CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);

            // call the function
            vm.prank(governance);
            lockerHarness.cancelLocker();
        }
    }

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        vm.prank(governance);
        locker.cancelLocker();

        assertEq(uint256(locker.state()), uint256(LockerPreLaunch.STATE.CANCELED));
    }
}
