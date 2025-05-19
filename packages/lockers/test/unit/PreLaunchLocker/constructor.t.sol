// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {PreLaunchLocker, ILiquidityGaugeV4} from "src/common/locker/PreLaunchLocker.sol";
import {sdToken as SdToken} from "src/common/token/sdToken.sol";
import {PreLaunchLockerTest, GaugeMock} from "test/unit/PreLaunchLocker/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__constructor is PreLaunchLockerTest {
    function test_RevertsIfTheGivenTokenIs0() external {
        // it reverts if the given token is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        new PreLaunchLocker(address(0), makeAddr("sdToken"), makeAddr("gauge"), 0);
    }

    function test_RevertIfTheGivenSdTokenIs0() external {
        // it revert if the given sdToken is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        new PreLaunchLocker(makeAddr("token"), address(0), makeAddr("gauge"), 0);
    }

    function test_RevertIfTheGivenGaugeIs0() external {
        // it revert if the given gauge is 0

        vm.expectRevert(PreLaunchLocker.REQUIRED_PARAM.selector);
        new PreLaunchLocker(makeAddr("token"), makeAddr("sdToken"), address(0), 0);
    }

    function test_RevertIfTheGaugeIsNotAssociatedWithTheGivenSdToken(address incorrectLpToken) external {
        // it revert if the gauge is not associated with the given sdToken

        vm.assume(incorrectLpToken != address(0));
        vm.assume(incorrectLpToken != address(sdToken));

        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(ILiquidityGaugeV4.staking_token.selector),
            abi.encode(incorrectLpToken)
        );

        vm.expectRevert(PreLaunchLocker.INVALID_GAUGE.selector);
        new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    function test_SetsTheTokenToTheGivenAddress(address token) external {
        // it sets the token to the given address

        vm.assume(token != address(0));

        PreLaunchLocker locker = new PreLaunchLocker(token, address(sdToken), address(gauge), 0);
        assertEq(locker.token(), token);
    }

    function test_SetsTheSdTokenToTheGivenAddress(bytes32 salt) external {
        // it sets the sdToken to the given address

        address _sdToken = address(new SdToken{salt: salt}("sdToken", "sdTOKEN"));
        address _gauge = address(new GaugeMock(_sdToken));

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), _sdToken, _gauge, 0);
        assertEq(address(locker.sdToken()), _sdToken);
    }

    function test_SetsTheGaugeToTheGivenAddress(bytes32 salt) external {
        // it sets the gauge to the given address

        address _sdToken = address(new SdToken{salt: salt}("sdToken", "sdTOKEN"));
        address _gauge = address(new GaugeMock(_sdToken));

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), _sdToken, _gauge, 0);
        assertEq(address(locker.gauge()), _gauge);
    }

    function test_SetsTheTimestampToTheCurrentTimestamp(uint96 timestamp) external {
        // it sets the timestamp to the current timestamp

        vm.warp(timestamp);

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
        assertEq(locker.timestamp(), timestamp);
    }

    function test_SetsTheStateToIDLE() external {
        // it sets the state to IDLE

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
        assertEq(uint256(locker.state()), uint256(PreLaunchLocker.STATE.IDLE));
    }

    function test_SetsTheGovernanceToTheCaller(address caller) external {
        // it sets the governance to the caller

        vm.assume(caller != address(0));

        vm.prank(caller);
        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);

        assertEq(locker.governance(), caller);
    }

    function test_SetsTheDefaultValueGivenNoCustomForceCancelDelay() external {
        // it sets the default value given no custom force cancel delay

        PreLaunchLocker locker = new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
        assertEq(locker.FORCE_CANCEL_DELAY(), 3 * 30 days);
    }

    function test_SetsTheCustomForceCancelDelayIfProvided(uint256 customForceCancelDelay) external {
        // it sets the custom force cancel delay if provided

        vm.assume(customForceCancelDelay != 0);

        PreLaunchLocker locker =
            new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), customForceCancelDelay);
        assertEq(locker.FORCE_CANCEL_DELAY(), customForceCancelDelay);
    }

    function test_EmitsTheStateUpdateEvent() external {
        // it emits the StateUpdate event

        vm.expectEmit(true, true, true, true);
        emit LockerStateUpdated(PreLaunchLocker.STATE.IDLE);
        new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    function test_EmitsTheGovernanceUpdatedEvent(address caller) external {
        // it emits the GovernanceUpdated event

        vm.assume(caller != address(0));

        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(address(0), caller);

        vm.prank(caller);
        new PreLaunchLocker(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    // FIXME: idk why I cannot import the events directly from the PreLaunchLocker contract
    //        by doing `PreLaunchLocker.GovernanceUpdated` so for now I'm just going to copy-paste
    //        them here.
    event LockerStateUpdated(PreLaunchLocker.STATE newState);
    event GovernanceUpdated(address previousGovernanceAddress, address newGovernanceAddress);
}
