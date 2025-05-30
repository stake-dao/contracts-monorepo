// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LockerPreLaunch} from "src/LockerPreLaunch.sol";
import {PreLaunchLockerTest} from "test/unit/LockerPreLaunch/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__getUserFriendlyStateLabel is PreLaunchLockerTest {
    function test_ReturnsDifferentValuesBasedOnTheState() external view {
        // it returns different values based on the state

        string memory idleLabel = locker.getUserFriendlyStateLabel(LockerPreLaunch.STATE.IDLE);
        string memory activeLabel = locker.getUserFriendlyStateLabel(LockerPreLaunch.STATE.ACTIVE);
        string memory canceledLabel = locker.getUserFriendlyStateLabel(LockerPreLaunch.STATE.CANCELED);

        assertNotEq(idleLabel, "");
        assertNotEq(idleLabel, activeLabel);
        assertNotEq(idleLabel, canceledLabel);
        assertNotEq(activeLabel, canceledLabel);
    }
}
