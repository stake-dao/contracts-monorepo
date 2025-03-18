// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/PreLaunchLocker.sol";
import {Test} from "forge-std/src/Test.sol";

contract PreLaunchLocker__constructor is Test {
    function test_RevertsIfTheGivenTokenIs0() external {
        // it reverts if the given token is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        new PreLaunchLocker(address(0));
    }

    function test_SetsTheStateToIDLE() external {
        // it sets the state to IDLE

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"));
        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.IDLE));
    }

    function test_SetsTheTokenToTheGivenAddress(address token) external {
        // it sets the token to the given address

        vm.assume(token != address(0));

        PreLaunchLocker locker = new PreLaunchLocker(token);
        assertEq(locker.token(), token);
    }

    function test_SetsTheGovernanceToTheSender() external {
        // it sets the governance to the sender

        address governance = makeAddr("governance");
        vm.prank(governance);
        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"));
        assertEq(locker.governance(), governance);
    }

    function test_SetsTheTimestampToTheCurrentTimestamp(uint96 timestamp) external {
        // it sets the timestamp to the current timestamp

        vm.warp(timestamp);

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"));
        assertEq(locker.timestamp(), timestamp);
    }

    function test_EmitsTheStateUpdateEvent() external {
        // it emits the StateUpdate event

        vm.expectEmit(true, true, true, true);
        emit LockerStateUpdated(PreLaunchLocker.STATE.IDLE);
        new PreLaunchLocker(makeAddr("token"));
    }

    function test_EmitsTheGovernanceUpdatedEvent() external {
        // it emits the GovernanceUpdated event

        address governance = makeAddr("governance");

        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(address(0), governance);

        vm.prank(governance);
        new PreLaunchLocker(makeAddr("token"));
    }

    // FIXME: idk why I cannot import the events directly from the PreLaunchLocker contract
    //        by doing `PreLaunchLocker.GovernanceUpdated` so for now I'm just going to copy-paste
    //        them here.
    event LockerStateUpdated(PreLaunchLocker.STATE newState);
    event GovernanceUpdated(address previousGovernanceAddress, address newGovernanceAddress);
}
