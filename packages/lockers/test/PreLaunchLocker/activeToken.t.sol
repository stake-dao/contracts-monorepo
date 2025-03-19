// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";

contract PreLaunchLocker__activeToken is Test {
    PreLaunchLockerHarness private locker;

    function setUp() public {
        locker = new PreLaunchLockerHarness(makeAddr("token"));
    }

    function test_ReturnsTheTokenWhenTheStateIsIDLE() external {
        // it returns the token when the state is IDLE

        // manually force the state to IDLE
        locker._cheat_setState(PreLaunchLocker.STATE.IDLE);
        assertEq(locker.activeToken(), locker.token());
    }

    function test_ReturnsTheTokenWhenTheStateIsCANCELED() external {
        // it returns the token when the state is CANCELED

        // manually force the state to CANCELED
        locker._cheat_setState(PreLaunchLocker.STATE.CANCELED);
        assertEq(locker.activeToken(), locker.token());
    }

    function test_ReturnsTheSdTokenWhenTheStateIsACTIVE() external {
        // it returns the sdToken when the state is ACTIVE

        // manually force the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);
        assertEq(locker.activeToken(), locker.sdToken());
    }
}
