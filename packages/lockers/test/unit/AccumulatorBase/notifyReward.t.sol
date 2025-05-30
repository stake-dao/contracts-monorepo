// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {BaseAccumulator__chargeFee} from "test/unit/AccumulatorBase/chargeFee.t.sol";

contract BaseAccumulator__notifyReward is BaseAccumulator__chargeFee {
    function setUp() public virtual override {
        super.setUp();

        // set the fee receiver
        vm.prank(baseAccumulator.governance());
        baseAccumulator.setFeeReceiver(address(feeReceiver));
    }

    function test_CallsFeeReceiverOnDemandIfThereIsOne() external {
        // it calls fee receiver on demand if there is one

        // expect the fee receiver to be called
        vm.expectCall(address(feeReceiver), abi.encodeWithSelector(IFeeReceiver.split.selector, address(rewardToken)));
        baseAccumulator.notifyReward(address(rewardToken));
    }

    function test_CallsTheGaugeToDepositTokensIfThereAreSome() external {
        // it calls the gauge to deposit tokens if there are some

        // calculate the expected charged fee (fee receivers + claimer)
        uint256 expectedChargedFee = _calculateExpectedChargedFee(initialBalance);

        // expect the gauge to be called with the expected charged fee
        vm.expectCall(
            address(gauge),
            abi.encodeWithSelector(
                ILiquidityGauge.deposit_reward_token.selector, address(rewardToken), initialBalance - expectedChargedFee
            )
        );

        baseAccumulator.notifyReward(address(rewardToken));
    }

    function test_ChargesTheFees() external {
        // it charges the fees

        // assert that the balance of the reward token is the initial balance
        assertEq(ERC20(address(rewardToken)).balanceOf(address(baseAccumulator)), initialBalance);

        baseAccumulator.notifyReward(address(rewardToken));

        // assert that the balance of the reward token is 0
        assertEq(ERC20(address(rewardToken)).balanceOf(address(baseAccumulator)), 0);
    }
}
