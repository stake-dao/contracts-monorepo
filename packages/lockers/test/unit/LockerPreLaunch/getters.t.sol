// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {PreLaunchLockerTest} from "test/unit/LockerPreLaunch/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__getters is PreLaunchLockerTest {
    function test_ExposesTheForceCancelDelay() external view {
        // it exposes the force cancel delay

        assertEq(locker.FORCE_CANCEL_DELAY(), 3 * 30 days);
    }

    function test_ExposesTheToken() external view {
        // it exposes the token

        assertNotEq(locker.token(), address(0));
    }

    function test_ExposesTheSdToken() external view {
        // it exposes the sdToken

        assertNotEq(locker.token(), address(0));
    }

    function test_ExposesTheGauge() external view {
        // it exposes the gauge

        assertNotEq(locker.token(), address(0));
    }

    function test_ExposesTheGovernance() external view {
        // it exposes the governance

        assertNotEq(locker.governance(), address(0));
    }

    function test_ExposesTheTimestamp() external view {
        // it exposes the timestamp

        assertEq(locker.timestamp(), 0);
    }

    function skip_test_ExposesTheDepositor(address depositor)
        external
        _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness
    {
        // it exposes the depositor

        lockerHarness._cheat_depositor(depositor);
        assertNotEq(address(lockerHarness.depositor()), address(0));
    }

    function test_ExposesTheState() external _cheat_replacePreLaunchLockerWithPreLaunchLockerHarness {
        // it exposes the state

        lockerHarness._cheat_state(LockerPreLaunch.STATE.ACTIVE);
        assertNotEq(uint256(lockerHarness.state()), 0);
    }
}
