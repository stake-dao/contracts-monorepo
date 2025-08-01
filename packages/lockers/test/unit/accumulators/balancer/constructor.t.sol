// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "@address-book/src/BalancerEthereum.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {BalancerAccumulator} from "src/integrations/balancer/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract BalancerAccumulator__constructor is AccumulatorTest {
    constructor() AccumulatorTest(Common.USDC, BalancerProtocol.BAL, BalancerLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new BalancerAccumulator(gauge, locker, governance, locker));
    }

    function test_SetsTheGivenGauge(address _gauge) external assumeNotZero(_gauge) {
        // it sets the given gauge

        vm.assume(_gauge != address(0));

        BalancerAccumulator balancerAccumulator = new BalancerAccumulator(_gauge, locker, governance, locker);
        assertEq(balancerAccumulator.gauge(), _gauge);
    }

    function test_SetsUSDCAsTheRewardToken() external view {
        // it sets USDC as the reward token

        assertEq(BalancerAccumulator(accumulator).rewardToken(), Common.USDC);
    }

    function test_SetsTheGivenLocker(address _locker) external assumeNotZero(_locker) {
        // it sets the given locker

        vm.assume(_locker != address(0));

        BalancerAccumulator balancerAccumulator = new BalancerAccumulator(gauge, _locker, governance, _locker);
        assertEq(balancerAccumulator.locker(), _locker);
    }

    function test_SetsTheGivenGovernance(address _governance) external assumeNotZero(_governance) {
        // it sets the given governance

        vm.assume(_governance != address(0));

        BalancerAccumulator balancerAccumulator = new BalancerAccumulator(gauge, locker, _governance, locker);
        assertEq(balancerAccumulator.governance(), _governance);
    }

    function test_SetsBALAsTheToken() external view {
        // it sets BAL as the token

        assertEq(BalancerAccumulator(accumulator).token(), BalancerProtocol.BAL);
    }

    function test_SetsVeBALAsTheVeToken() external view {
        // it sets veBAL as the veToken

        assertEq(BalancerAccumulator(accumulator).veToken(), BalancerProtocol.VEBAL);
    }

    function test_SetsTheCorrectVeBoostContract() external view {
        // it sets the correct veBoost contract

        assertEq(BalancerAccumulator(accumulator).veBoost(), BalancerProtocol.VE_BOOST);
    }

    function test_SetsTheCorrectVeBoostDelegationContract() external view {
        // it sets the correct veBoost delegation contract

        assertEq(BalancerAccumulator(accumulator).veBoostDelegation(), BalancerLocker.VE_BOOST_DELEGATION);
    }

    function test_Sets0AsTheMultiplier() external view {
        // it sets 0 as the multiplier

        assertEq(BalancerAccumulator(accumulator).multiplier(), 0);
    }

    function test_SetsTheGivenGateway(address _gateway) external assumeNotZero(_gateway) {
        // it sets the given gateway

        vm.assume(_gateway != address(0));

        BalancerAccumulator balancerAccumulator = new BalancerAccumulator(gauge, locker, governance, _gateway);
        assertEq(balancerAccumulator.GATEWAY(), _gateway);
    }

    function test_GivesFullApprovalToTheGaugeForTheBALAndUSDCTokens() external view {
        // it gives full approval to the gauge for the BAL and USDC tokens

        assertEq(ERC20(Common.USDC).allowance(address(accumulator), gauge), type(uint256).max);
        assertEq(ERC20(BalancerProtocol.BAL).allowance(address(accumulator), gauge), type(uint256).max);
    }

    modifier assumeNotZero(address _address) {
        vm.assume(_address != address(0));

        _;
    }
}
