// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";

contract PreLaunchLocker__getUserFriendlyStateLabel is Test {
    function test_ReturnsDifferentValuesBasedOnTheState() external {
        // it returns different values based on the state

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"));

        string memory idleLabel = locker.getUserFriendlyStateLabel(PreLaunchLocker.STATE.IDLE);
        string memory activeLabel = locker.getUserFriendlyStateLabel(PreLaunchLocker.STATE.ACTIVE);
        string memory canceledLabel = locker.getUserFriendlyStateLabel(PreLaunchLocker.STATE.CANCELED);

        assertNotEq(idleLabel, "");
        assertNotEq(idleLabel, activeLabel);
        assertNotEq(idleLabel, canceledLabel);
        assertNotEq(activeLabel, canceledLabel);
    }
}
