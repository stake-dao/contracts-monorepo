// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/PreLaunchLocker.sol";

contract PreLaunchLocker__receive is Test {
    bool internal sent;
    bytes internal data;

    function test_RevertsOnAnyETHDeposit() external {
        // it reverts on any ETH deposit

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr(""));

        vm.expectRevert("PreLaunchLocker: cannot receive ETH");
        (sent, data) = address(locker).call{value: 1 ether}("");

        vm.expectRevert("PreLaunchLocker: cannot receive ETH");
        payable(address(locker)).transfer(1 ether);

        vm.expectRevert("PreLaunchLocker: cannot receive ETH");
        sent = payable(address(locker)).send(1 ether);
    }
}
