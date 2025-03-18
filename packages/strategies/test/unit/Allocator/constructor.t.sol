// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Allocator} from "src/Allocator.sol";
import {BaseTest} from "test/Base.t.sol";

contract Allocator__constructor is BaseTest {
    function test_SetsTheGatewayToTheGivenGateway(address gateway) external {
        // it sets the gateway to the given gateway

        vm.assume(gateway != address(0));

        Allocator allocator = new Allocator(makeAddr("locker"), gateway);
        assertEq(allocator.GATEWAY(), gateway);
    }

    function test_SetsTheGatewayToTheLockerIfLockerIsAddress0() external {
        // it sets the gateway to the locker if locker is address 0

        Allocator allocator = new Allocator(address(0), makeAddr("gateway"));
        assertEq(allocator.LOCKER(), makeAddr("gateway"));
    }

    function test_SetsTheLockerToTheGivenLockerIfLockerIsNotAddress0(address locker) external {
        // it sets the locker to the given locker if locker is not address 0

        vm.assume(address(locker) != address(0));

        Allocator allocator = new Allocator(locker, makeAddr("gateway"));
        assertEq(allocator.LOCKER(), locker);
    }

    function test_RevertsIfTheGatewayIsZeroAddress() external {
        // it reverts if the gateway is zero address

        vm.expectRevert(Allocator.GatewayZeroAddress.selector);
        new Allocator(makeAddr("locker"), address(0));
    }
}
