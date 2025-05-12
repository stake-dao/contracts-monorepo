// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Yearn} from "address-book/src/protocols/1.sol";
import {YFI} from "address-book/src/lockers/1.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";
import {YearnDepositor} from "src/mainnet/yearn/Depositor.sol";
import {YearnDepositorHarness} from "test/unit/depositors/yearn/YearnDepositorHarness.sol";
import {IVeYFI} from "src/common/interfaces/IVeYFI.sol";

contract YearnDepositor__lockToken is DepositorTest {
    function test_IncreasesTheAmountAndTheUnlockTimeIfNeeded(
        uint256 amount,
        uint128 timestamp,
        uint128 lockedEndTimestamp
    ) external {
        // it increases the amount and the unlock time if needed

        // set block.timestamp to the fuzzed timestamp
        vm.warp(timestamp);

        // mock the `locked` function to return the fuzzed locked end timestamp
        IVeYFI.LockedBalance memory lockedBalance = IVeYFI.LockedBalance({amount: amount, end: lockedEndTimestamp});
        vm.mockCall(address(veToken), abi.encodeWithSelector(IVeYFI.locked.selector, locker), abi.encode(lockedBalance));

        // check if the unlock time shall be increased and calculate the new unlock time
        bool willIncreaseUnlockTime =
            (block.timestamp + YearnDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks > lockedEndTimestamp;
        uint256 newUnlockTime =
            willIncreaseUnlockTime ? block.timestamp + YearnDepositor(depositor).MAX_LOCK_DURATION() : 0;

        // expect the `modify_lock` function to be called with the correct parameters the correct number of times
        if (amount == 0 && newUnlockTime == 0) {
            vm.expectCall(address(veToken), abi.encodeWithSelector(IVeYFI.modify_lock.selector), 0);
        } else if (amount > 0 && newUnlockTime == 0) {
            vm.expectCall(address(veToken), abi.encodeWithSelector(IVeYFI.modify_lock.selector, amount, 0), 1);
        } else if (amount == 0 && newUnlockTime > 0) {
            vm.expectCall(address(veToken), abi.encodeWithSelector(IVeYFI.modify_lock.selector, 0, newUnlockTime), 1);
        } else if (amount > 0 && newUnlockTime > 0) {
            vm.expectCall(
                address(veToken), abi.encodeWithSelector(IVeYFI.modify_lock.selector, amount, newUnlockTime), 1
            );
        } else {
            revert("Invalid state");
        }

        YearnDepositorHarness(depositor)._expose_lockToken(amount);
    }

    function test_DoesNothingIfNoneTheAmountOrTheUnlockTimeIsPositive() external {
        // it does nothing if none the amount or the unlock time is positive

        // expect the veToken contract to not be called at all
        vm.expectCall(address(veToken), abi.encodeWithSelector(IVeYFI.modify_lock.selector), 0);

        // set the unlock time to the max lock duration
        uint256 _unlockTime = (block.timestamp + YearnDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks;

        // mock the `locked` function to return the locked balance
        IVeYFI.LockedBalance memory lockedBalance = IVeYFI.LockedBalance({amount: 0, end: _unlockTime});
        vm.mockCall(address(veToken), abi.encodeWithSelector(IVeYFI.locked.selector, locker), abi.encode(lockedBalance));

        YearnDepositorHarness(depositor)._expose_lockToken(0);
    }

    constructor() DepositorTest(Yearn.YFI, Yearn.VEYFI, YFI.GAUGE) {}

    function _deployDepositor() internal override returns (address) {
        return address(new YearnDepositorHarness(token, locker, minter, gauge, locker));
    }
}
