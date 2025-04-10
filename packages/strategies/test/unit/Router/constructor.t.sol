// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Router} from "src/Router.sol";

contract Router__constructor is Test {
    function test_SetsTheSenderAsOwner(address sender) external {
        // it sets the sender as owner

        vm.assume(sender != address(0));

        vm.prank(sender);
        Router router = new Router();

        assertEq(router.owner(), sender);
    }
}
