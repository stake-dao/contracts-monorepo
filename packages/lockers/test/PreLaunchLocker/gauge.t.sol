// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";
import {PreLaunchLockerHarness} from "./PreLaunchLockerHarness.t.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";

contract PreLaunchLocker__gauge is Test {
    using stdStorage for StdStorage;

    PreLaunchLockerHarness private locker;

    function setUp() public {
        locker = new PreLaunchLockerHarness(makeAddr("token"));
    }

    function test_ReturnsTheAddress0WhenTheStateIsIDLE() external {
        // it returns the address 0 when the state is IDLE

        // manually force the state to IDLE
        locker._cheat_setState(PreLaunchLocker.STATE.IDLE);
        assertEq(locker.gauge(), address(0));
    }

    function test_ReturnsTheAddress0WhenTheStateIsCANCELED() external {
        // it returns the address 0 when the state is CANCELED

        // manually force the state to CANCELED
        locker._cheat_setState(PreLaunchLocker.STATE.CANCELED);
        assertEq(locker.gauge(), address(0));
    }

    function test_ReturnsTheAddressOfTheGaugeWhenTheStateIsACTIVE(address gauge) external {
        // it returns the address of the gauge when the state is ACTIVE

        // manually force the state to ACTIVE
        locker._cheat_setState(PreLaunchLocker.STATE.ACTIVE);

        // deploy a new depositor mock
        DepositorMock depositor = new DepositorMock();

        // manually sets the depositor by cheating the slot
        stdstore.target(address(locker)).sig("depositor()").checked_write(address(depositor));

        // manually mock the call made to the depositor to return the gauge and return the fuzzed gauge address
        vm.mockCall(depositor.gauge(), abi.encodeWithSelector(DepositorMock.gauge.selector), abi.encode(gauge));

        assertEq(locker.gauge(), gauge);
    }
}

contract DepositorMock {
    function gauge() external view returns (address) {}
}
