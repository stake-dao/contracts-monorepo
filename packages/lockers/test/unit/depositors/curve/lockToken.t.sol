// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {IVeToken} from "src/interfaces/IVeToken.sol";
import {CurveDepositor} from "src/integrations/curve/Depositor.sol";
import {CurveDepositorHarness} from "test/unit/depositors/curve/CurveDepositorHarness.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";

contract CurveDepositor__lockToken is DepositorTest {
    constructor() DepositorTest(CurveProtocol.CRV, CurveProtocol.VECRV, CurveLocker.GAUGE) {}

    function test_IncreasesTheAmountAndTheUnlockTimeIfNeeded(
        uint256 amount,
        uint128 timestamp,
        uint128 lockedEndTimestamp
    ) external {
        // it increases the amount and the unlock time if needed

        // set block.timestamp to the fuzzed timestamp
        vm.warp(timestamp);

        // mock the `locked__end` function to return the fuzzed locked end timestamp
        vm.mockCall(
            address(veToken),
            abi.encodeWithSelector(IVeToken.locked__end.selector, locker),
            abi.encode(lockedEndTimestamp)
        );

        // expect the `increase_amount` function to be called if the amount is greater than 0
        if (amount > 0) {
            vm.expectCall(address(veToken), abi.encodeWithSelector(IVeToken.increase_amount.selector, amount), 1);
        }

        // check if the unlock time shall be increased
        bool willIncreaseUnlockTime =
            (block.timestamp + CurveDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks > lockedEndTimestamp;

        // expect the `increase_unlock_time` function to be called if the unlock time shall be increased
        if (willIncreaseUnlockTime) {
            vm.expectCall(
                address(veToken),
                abi.encodeWithSelector(
                    IVeToken.increase_unlock_time.selector,
                    block.timestamp + CurveDepositor(depositor).MAX_LOCK_DURATION()
                ),
                1
            );
        }

        CurveDepositorHarness(depositor)._expose_lockToken(amount);
    }

    function test_DoesNothingIfNoneTheAmountOrTheUnlockTimeIsPositive() external {
        // it does nothing if none the amount or the unlock time is positive

        // expect the veToken contract to not be called at all
        vm.expectCall(address(veToken), abi.encodeWithSelector(IVeToken.increase_unlock_time.selector), 0);
        vm.expectCall(address(veToken), abi.encodeWithSelector(IVeToken.increase_amount.selector), 0);

        // set the unlock time to the max lock duration
        uint256 _unlockTime = (block.timestamp + CurveDepositor(depositor).MAX_LOCK_DURATION()) / 1 weeks * 1 weeks;
        vm.mockCall(
            address(veToken), abi.encodeWithSelector(IVeToken.locked__end.selector, locker), abi.encode(_unlockTime)
        );

        CurveDepositorHarness(depositor)._expose_lockToken(0);
    }

    function _deployDepositor() internal override returns (address) {
        return address(new CurveDepositorHarness(token, locker, minter, gauge, locker));
    }
}
