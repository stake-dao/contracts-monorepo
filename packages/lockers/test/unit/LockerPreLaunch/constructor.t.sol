// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {LockerPreLaunch, ILiquidityGaugeV4} from "src/LockerPreLaunch.sol";
import {sdToken as SdToken} from "src/SDToken.sol";
import {PreLaunchLockerTest, GaugeMock} from "test/unit/LockerPreLaunch/utils/PreLaunchLockerTest.t.sol";

contract PreLaunchLocker__constructor is PreLaunchLockerTest {
    function test_RevertsIfTheGivenTokenIs0() external {
        // it reverts if the given token is 0

        vm.expectRevert(LockerPreLaunch.REQUIRED_PARAM.selector);
        new LockerPreLaunch(address(0), makeAddr("sdToken"), makeAddr("gauge"), 0);
    }

    function test_RevertIfTheGivenSdTokenIs0() external {
        // it revert if the given sdToken is 0

        vm.expectRevert(LockerPreLaunch.REQUIRED_PARAM.selector);
        new LockerPreLaunch(makeAddr("token"), address(0), makeAddr("gauge"), 0);
    }

    function test_RevertIfTheGivenGaugeIs0() external {
        // it revert if the given gauge is 0

        vm.expectRevert(LockerPreLaunch.REQUIRED_PARAM.selector);
        new LockerPreLaunch(makeAddr("token"), makeAddr("sdToken"), address(0), 0);
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

        vm.expectRevert(LockerPreLaunch.INVALID_GAUGE.selector);
        new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    function test_SetsTheTokenToTheGivenAddress(address token) external {
        // it sets the token to the given address

        vm.assume(token != address(0));

        LockerPreLaunch locker = new LockerPreLaunch(token, address(sdToken), address(gauge), 0);
        assertEq(locker.token(), token);
    }

    function test_SetsTheSdTokenToTheGivenAddress(bytes32 salt) external {
        // it sets the sdToken to the given address

        address _sdToken = address(new SdToken{salt: salt}("sdToken", "sdTOKEN"));
        address _gauge = address(new GaugeMock(_sdToken));

        LockerPreLaunch locker = new LockerPreLaunch(makeAddr("token"), _sdToken, _gauge, 0);
        assertEq(address(locker.sdToken()), _sdToken);
    }

    function test_SetsTheGaugeToTheGivenAddress(bytes32 salt) external {
        // it sets the gauge to the given address

        address _sdToken = address(new SdToken{salt: salt}("sdToken", "sdTOKEN"));
        address _gauge = address(new GaugeMock(_sdToken));

        LockerPreLaunch locker = new LockerPreLaunch(makeAddr("token"), _sdToken, _gauge, 0);
        assertEq(address(locker.gauge()), _gauge);
    }

    function test_SetsTheStateToIDLE() external {
        // it sets the state to IDLE

        LockerPreLaunch locker = new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);
        assertEq(uint256(locker.state()), uint256(LockerPreLaunch.STATE.IDLE));
    }

    function test_SetsTheGovernanceToTheCaller(address caller) external {
        // it sets the governance to the caller

        vm.assume(caller != address(0));

        vm.prank(caller);
        LockerPreLaunch locker = new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);

        assertEq(locker.governance(), caller);
    }

    function test_SetsTheDefaultValueGivenNoCustomForceCancelDelay() external {
        // it sets the default value given no custom force cancel delay

        LockerPreLaunch locker = new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);
        assertEq(locker.FORCE_CANCEL_DELAY(), 3 * 30 days);
    }

    function test_SetsTheCustomForceCancelDelayIfProvided(uint256 customForceCancelDelay) external {
        // it sets the custom force cancel delay if provided

        vm.assume(customForceCancelDelay != 0);

        LockerPreLaunch locker =
            new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), customForceCancelDelay);
        assertEq(locker.FORCE_CANCEL_DELAY(), customForceCancelDelay);
    }

    function test_DoesntSetTheTimestamp() external {
        assertEq(locker.timestamp(), 0);
    }

    function test_EmitsTheStateUpdateEvent() external {
        // it emits the StateUpdate event

        vm.expectEmit(true, true, true, true);
        emit LockerStateUpdated(LockerPreLaunch.STATE.IDLE);
        new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    function test_EmitsTheGovernanceUpdatedEvent(address caller) external {
        // it emits the GovernanceUpdated event

        vm.assume(caller != address(0));

        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(address(0), caller);

        vm.prank(caller);
        new LockerPreLaunch(makeAddr("token"), address(sdToken), address(gauge), 0);
    }

    // FIXME: idk why I cannot import the events directly from the LockerPreLaunch contract
    //        by doing `LockerPreLaunch.GovernanceUpdated` so for now I'm just going to copy-paste
    //        them here.
    event LockerStateUpdated(LockerPreLaunch.STATE newState);
    event GovernanceUpdated(address previousGovernanceAddress, address newGovernanceAddress);
}
