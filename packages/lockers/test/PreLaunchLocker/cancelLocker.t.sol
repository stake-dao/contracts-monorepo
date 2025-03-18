// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/PreLaunchLocker.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";

contract PreLaunchLocker__cancelLocker is Test {
    PreLaunchLockerHarness private locker;
    address private governance;

    function setUp() public {
        governance = makeAddr("governance");

        vm.prank(governance);
        locker = new PreLaunchLockerHarness(makeAddr("token"));
    }

    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(PreLaunchLocker.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.cancelLocker();
    }

    function test_RevertsIfTheStateIsNotIDLE() external {
        // it reverts if the state is not IDLE

        PreLaunchLocker.STATE[2] memory states = [PreLaunchLocker.STATE.ACTIVE, PreLaunchLocker.STATE.CANCELED];

        for (uint256 i; i < states.length; i++) {
            // manually set the state to the given state
            locker._cheat_setState(states[i]);

            // expect the revert
            vm.expectRevert(PreLaunchLocker.CANNOT_CANCEL_ACTIVE_OR_CANCELED_LOCKER.selector);

            // call the function
            vm.prank(governance);
            locker.cancelLocker();
        }
    }

    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        vm.prank(governance);
        locker.cancelLocker();

        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.CANCELED));
    }
}
