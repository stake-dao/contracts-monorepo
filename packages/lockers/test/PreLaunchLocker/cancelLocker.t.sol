// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerTest} from "test/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__cancelLocker is PreLaunchLockerTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(PreLaunchLocker.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.cancelLocker();
    }

    function test_RevertsIfTheStateIsNotIDLE() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it reverts if the state is not IDLE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            lockerHarness._cheat_state(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);

            // call the function
            vm.prank(governance);
            lockerHarness.cancelLocker();
        }
    }

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        vm.prank(governance);
        locker.cancelLocker();

        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.CANCELED));
    }
}
