// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DepositorBase} from "src/DepositorBase.sol";
import {BaseDepositorTest} from "./utils/BaseDepositorTest.t.sol";

contract BaseDepositor__createLock is BaseDepositorTest {
    function test_RevertsIfTheStateIsCANCELED() external {
        // it reverts if the state is CANCELED

        vm.prank(governance);
        baseDepositor.shutdown();

        vm.expectRevert(DepositorBase.DEPOSITOR_DISABLED.selector);
        baseDepositor.createLock(100);
    }
}
