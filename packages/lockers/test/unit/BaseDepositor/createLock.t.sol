// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {BaseDepositorTest} from "./utils/BaseDepositorTest.t.sol";

contract BaseDepositor__createLock is BaseDepositorTest {
    function test_RevertsIfTheStateIsCANCELED() external {
        // it reverts if the state is CANCELED

        vm.prank(governance);
        baseDepositor.shutdown();

        vm.expectRevert(BaseDepositor.DEPOSITOR_DISABLED.selector);
        baseDepositor.createLock(100);
    }
}
