// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolController} from "src/ProtocolController.sol";
import {BaseTest} from "test/Base.t.sol";

contract ProtocolController__constructor is BaseTest {
    function test_InitializesTheOwner(address caller) external {
        // it initializes the owner

        vm.assume(caller != address(0));

        vm.prank(caller);
        ProtocolController controler = new ProtocolController(caller);
        assertEq(controler.owner(), caller);
    }
}
