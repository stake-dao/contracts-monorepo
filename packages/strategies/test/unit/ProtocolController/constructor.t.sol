// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {ProtocolController} from "src/ProtocolController.sol";

contract ProtocolController__constructor is BaseTest {
    function test_InitializesTheOwner(address caller) external {
        // it initializes the owner

        vm.assume(caller != address(0));

        vm.prank(caller);
        ProtocolController controler = new ProtocolController();
        assertEq(controler.owner(), caller);
    }
}
