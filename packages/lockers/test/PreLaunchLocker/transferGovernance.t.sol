// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";

contract PreLaunchLocker__transferGovernance is Test {
    PreLaunchLocker private locker;
    address private governance;

    function setUp() public {
        governance = makeAddr("governance");

        vm.prank(governance);
        locker = new PreLaunchLocker(makeAddr("token"));
    }

    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != governance);

        vm.expectRevert(PreLaunchLocker.ONLY_GOVERNANCE.selector);
        vm.prank(caller);
        locker.transferGovernance(makeAddr("newGovernance"));
    }

    function test_SetsTheNewGovernance(address newGovernance) external {
        // it sets the new governance

        vm.prank(governance);
        locker.transferGovernance(newGovernance);

        assertEq(locker.governance(), newGovernance);
    }

    function test_EmitTheUpdatedEvent(address newGovernance) external {
        // it emit the updated event

        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(governance, newGovernance);

        vm.prank(governance);
        locker.transferGovernance(newGovernance);
    }

    // FIXME: idk why I cannot import the events directly from the PreLaunchLocker contract
    //        by doing `PreLaunchLocker.GovernanceUpdated` so for now I'm just going to copy-paste
    //        them here.
    event GovernanceUpdated(address previousGovernanceAddress, address newGovernanceAddress);
}
