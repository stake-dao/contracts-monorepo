// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Test} from "forge-std/src/Test.sol";
import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";
import {Test} from "forge-std/src/Test.sol";
import {YFI as YearnLocker} from "address-book/src/lockers/1.sol";
import {Yearn as YearnProtocol} from "address-book/src/protocols/1.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract YearnAccumulator__constructor is AccumulatorTest {
    constructor() AccumulatorTest(YearnLocker.TOKEN, YearnProtocol.DYFI, YearnLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new YearnAccumulator(gauge, locker, governance, locker));
    }

    function test_SetsTheGaugeToTheGivenValue(address _gauge) external {
        // it sets the gauge to the given value

        vm.assume(_gauge != address(0));

        YearnAccumulator yearnAccumulator = new YearnAccumulator(_gauge, locker, governance, locker);
        assertEq(yearnAccumulator.gauge(), _gauge);
    }

    function test_SetsTheLockerToTheGivenValue(address _locker) external {
        // it sets the locker to the given value

        vm.assume(_locker != address(0));

        YearnAccumulator yearnAccumulator = new YearnAccumulator(gauge, _locker, governance, _locker);
        assertEq(yearnAccumulator.locker(), _locker);
    }

    function test_SetsTheGovernanceToTheGivenValue(address _governance) external {
        // it sets the governance to the given value

        vm.assume(_governance != address(0));

        YearnAccumulator yearnAccumulator = new YearnAccumulator(gauge, locker, _governance, locker);
        assertEq(yearnAccumulator.governance(), _governance);
    }

    function test_SetsTheTokenToTheExpectedValue() external view {
        // it sets the token to the expected value

        assertEq(YearnAccumulator(accumulator).token(), YearnLocker.TOKEN);
    }

    function test_SetsTheRewardTokenToTheExpectedValue() external view {
        // it sets the reward token to the expected value

        assertEq(YearnAccumulator(accumulator).rewardToken(), YearnProtocol.DYFI);
    }

    function test_ApprovesTheGaugeForTheTokens() external view {
        // it approves the gauge for the tokens

        assertEq(MockERC20(token).allowance(address(accumulator), gauge), type(uint256).max);
        assertEq(MockERC20(rewardToken).allowance(address(accumulator), gauge), type(uint256).max);
    }

    function test_SetsThePoolsToTheExpectedValues() external view {
        // it sets the pools to the expected values

        assertEq(YearnAccumulator(accumulator).YFI_REWARD_POOL(), YearnProtocol.YFI_REWARD_POOL);
        assertEq(YearnAccumulator(accumulator).DYFI_REWARD_POOL(), YearnProtocol.DYFI_REWARD_POOL);
    }
}
