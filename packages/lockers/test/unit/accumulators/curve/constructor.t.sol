// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {CRV as CurveLocker} from "address-book/src/lockers/1.sol";
import {Curve} from "address-book/src/protocols/1.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {CurveAccumulator} from "src/mainnet/curve/Accumulator.sol";
import {AccumulatorTest} from "test/unit/accumulators/AccumulatorTest.t.sol";

contract CurveAccumulator__constructor is AccumulatorTest {
    constructor() AccumulatorTest(Curve.CRV_USD, Curve.CRV, CurveLocker.GAUGE) {}

    function _deployAccumulator() internal override returns (address) {
        return address(new CurveAccumulator(gauge, locker, governance, locker));
    }

    function test_SetsTheGivenGauge(address _gauge) external assumeNotZero(_gauge) {
        // it sets the given gauge

        vm.assume(_gauge != address(0));

        CurveAccumulator curveAccumulator = new CurveAccumulator(_gauge, locker, governance, locker);
        assertEq(curveAccumulator.gauge(), _gauge);
    }

    function test_SetsCrvUSDAsTheRewardToken() external view {
        // it sets crvUSD as the reward token

        assertEq(CurveAccumulator(accumulator).rewardToken(), Curve.CRV_USD);
    }

    function test_SetsTheGivenLocker(address _locker) external assumeNotZero(_locker) {
        // it sets the given locker

        vm.assume(_locker != address(0));

        CurveAccumulator curveAccumulator = new CurveAccumulator(gauge, _locker, governance, _locker);
        assertEq(curveAccumulator.locker(), _locker);
    }

    function test_SetsTheGivenGovernance(address _governance) external assumeNotZero(_governance) {
        // it sets the given governance

        vm.assume(_governance != address(0));

        CurveAccumulator curveAccumulator = new CurveAccumulator(gauge, locker, _governance, locker);
        assertEq(curveAccumulator.governance(), _governance);
    }

    function test_SetsCRVAsTheToken() external view {
        // it sets CRV as the token

        assertEq(CurveAccumulator(accumulator).token(), Curve.CRV);
    }

    function test_SetsVeCRVAsTheVeToken() external view {
        // it sets veCRV as the veToken

        assertEq(CurveAccumulator(accumulator).veToken(), Curve.VECRV);
    }

    function test_SetsTheCorrectVeBoostContract() external view {
        // it sets the correct veBoost contract

        assertEq(CurveAccumulator(accumulator).veBoost(), Curve.VE_BOOST);
    }

    function test_SetsTheCorrectVeBoostDelegationContract() external view {
        // it sets the correct veBoost delegation contract

        assertEq(CurveAccumulator(accumulator).veBoostDelegation(), Curve.VE_BOOST_DELEGATION);
    }

    function test_Sets0AsTheMultiplier() external view {
        // it sets 0 as the multiplier

        assertEq(CurveAccumulator(accumulator).multiplier(), 0);
    }

    function test_SetsTheGivenGateway(address _gateway) external assumeNotZero(_gateway) {
        // it sets the given gateway

        vm.assume(_gateway != address(0));
        vm.assume(_gateway != locker);

        CurveAccumulator curveAccumulator = new CurveAccumulator(gauge, locker, governance, _gateway);
        assertEq(curveAccumulator.GATEWAY(), _gateway);
    }

    function test_GivesFullApprovalToTheGaugeForTheCRVAndCRV_USDTokens() external view {
        // it gives full approval to the gauge for the CRV and CRV_USD tokens

        assertEq(
            ERC20(Curve.CRV).allowance(address(accumulator), CurveAccumulator(accumulator).gauge()), type(uint256).max
        );
        assertEq(
            ERC20(Curve.CRV_USD).allowance(address(accumulator), CurveAccumulator(accumulator).gauge()),
            type(uint256).max
        );
    }

    modifier assumeNotZero(address _address) {
        vm.assume(_address != address(0));

        _;
    }
}
