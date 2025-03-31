// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {BaseDepositorTest} from "./utils/BaseDepositorTest.t.sol";

contract BaseDepositor__shutdown is BaseDepositorTest {
    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        assertEq(uint256(baseDepositor.state()), uint256(BaseDepositor.STATE.ACTIVE));

        vm.prank(governance);
        baseDepositor.shutdown();

        assertEq(uint256(baseDepositor.state()), uint256(BaseDepositor.STATE.CANCELED));
    }

    function test_EmitsTheStateUpdatedEvent() external {
        // it emits the StateUpdated event

        vm.expectEmit(true, true, true, true);
        emit StateUpdated(BaseDepositor.STATE.CANCELED);

        vm.prank(governance);
        baseDepositor.shutdown();
    }

    event StateUpdated(BaseDepositor.STATE newState);
}
