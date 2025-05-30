// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DepositorBase} from "src/DepositorBase.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {DepositorBaseContract} from "test/unit/DepositorBase/utils/BaseDepositorTest.t.sol";

contract BaseDepositor__constructor is BaseTest {
    address internal minter = address(new MinterMocker());

    function test_RevertIfTheTokenIsTheZeroAddress() external {
        // it revert if the token is the zero address

        vm.expectRevert(DepositorBase.ADDRESS_ZERO.selector);
        new DepositorBaseContract(address(0), makeAddr("locker"), makeAddr("minter"), makeAddr("gauge"), 100);
    }

    function test_RevertIfTheLockerIsTheZeroAddress() external {
        // it revert if the locker is the zero address

        vm.expectRevert(DepositorBase.ADDRESS_ZERO.selector);
        new DepositorBaseContract(makeAddr("token"), address(0), makeAddr("minter"), makeAddr("gauge"), 100);
    }

    function test_RevertIfTheMinterIsTheZeroAddress() external {
        // it revert if the minter is the zero address

        vm.expectRevert(DepositorBase.ADDRESS_ZERO.selector);
        new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), address(0), makeAddr("gauge"), 100);
    }

    function test_RevertIfTheGaugeIsTheZeroAddress() external {
        // it revert if the gauge is the zero address

        vm.expectRevert(DepositorBase.ADDRESS_ZERO.selector);
        new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), makeAddr("minter"), address(0), 100);
    }

    function test_SetsTheGovernanceToTheCaller(address caller) external {
        // it sets the governance to the caller

        vm.assume(caller != address(0));

        vm.prank(caller);
        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(depositor.governance(), caller);
    }

    function test_SetsTheToken() external {
        // it sets the token

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(depositor.token(), makeAddr("token"));
    }

    function test_SetsTheLocker() external {
        // it sets the locker

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(depositor.locker(), makeAddr("locker"));
    }

    function test_SetsTheMinter() external {
        // it sets the minter

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(depositor.minter(), minter);
    }

    function test_SetsTheGauge() external {
        // it sets the gauge

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(depositor.gauge(), makeAddr("gauge"));
    }

    function test_SetsTheMaxLockDurationToTheGivenValue(uint256 maxLockDuration) external {
        // it sets the max lock duration to the given value

        vm.assume(maxLockDuration > 0);

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), maxLockDuration);

        assertEq(depositor.MAX_LOCK_DURATION(), maxLockDuration);
    }

    function test_SetsTheStateToACTIVE() external {
        // it sets the state to ACTIVE

        DepositorBaseContract depositor =
            new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);

        assertEq(uint256(depositor.state()), uint256(DepositorBase.STATE.ACTIVE));
    }

    function test_ApprovesTheGaugeWithMaxUint256() external {
        // it approves the gauge with max uint256

        vm.expectCall(address(minter), abi.encodeCall(MinterMocker.approve, (makeAddr("gauge"), type(uint256).max)), 1);

        new DepositorBaseContract(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), 100);
    }
}

contract MinterMocker {
    function approve(address, uint256) external pure returns (bool) {
        return true;
    }
}
