// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Pendle} from "address-book/src/protocols/1.sol";
import {PENDLE} from "address-book/src/lockers/1.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";
import {PendleDepositor} from "src/mainnet/pendle/Depositor.sol";
import {PendleDepositorHarness} from "test/unit/depositors/pendle/PendleDepositorHarness.sol";
import {IVePendle} from "src/common/interfaces/IVePendle.sol";

contract PendleDepositor__lockToken is DepositorTest {
    function test_IncreasesTheAmountAndTheUnlockTimeIfNeeded(
        uint128 amount,
        uint96 timestamp,
        uint96 lockedEndTimestamp
    ) external {
        // it increases the amount and the unlock time if needed

        // set block.timestamp to the fuzzed timestamp
        vm.warp(timestamp);

        // mock the `positionData` function to return the fuzzed locked end timestamp
        vm.mockCall(
            address(veToken),
            abi.encodeWithSelector(IVePendle.positionData.selector, locker),
            abi.encode(uint128(0), uint128(lockedEndTimestamp))
        );

        // check if the unlock time shall be increased and calculate the new unlock time
        uint256 unlockTime = (block.timestamp + PendleDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks;
        uint256 newUnlockTime = unlockTime > lockedEndTimestamp ? unlockTime : lockedEndTimestamp;

        // expect the `increaseLockPosition` function to be called once with the correct parameters
        vm.expectCall(
            address(veToken), abi.encodeWithSelector(IVePendle.increaseLockPosition.selector, amount, newUnlockTime), 1
        );

        PendleDepositorHarness(depositor)._expose_lockToken(amount);
    }

    function test_DoesNothingIfNoneTheAmountOrTheUnlockTimeIsPositive() external {
        // it does nothing if none the amount or the unlock time is positive

        uint256 unlockTime = (block.timestamp + PendleDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks;

        // mock the `positionData` function to return an expiry position equals to the current unlock time
        vm.mockCall(
            address(veToken),
            abi.encodeWithSelector(IVePendle.positionData.selector, locker),
            abi.encode(uint128(0), uint128(unlockTime))
        );

        // expect the veToken contract to be called once with 0 amount and the already set unlock time
        vm.expectCall(
            address(veToken), abi.encodeWithSelector(IVePendle.increaseLockPosition.selector, 0, unlockTime), 1
        );

        PendleDepositorHarness(depositor)._expose_lockToken(0);
    }

    constructor() DepositorTest(Pendle.PENDLE, Pendle.VEPENDLE, PENDLE.GAUGE) {}

    function _deployDepositor() internal override returns (address) {
        return address(new PendleDepositorHarness(token, locker, minter, gauge, locker));
    }
}
