// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__chargeFee is BaseAccumulatorTest {
    uint256 internal initialBalance = 1e20;

    function setUp() public virtual override {
        super.setUp();

        // set the initial fee split
        AccumulatorBase.Split[] memory splits = new AccumulatorBase.Split[](2);
        splits[0] = AccumulatorBase.Split({receiver: makeAddr("receiver1"), fee: 1e17});
        splits[1] = AccumulatorBase.Split({receiver: makeAddr("receiver2"), fee: 5e17});

        vm.prank(baseAccumulator.governance());
        baseAccumulator.setFeeSplit(splits);

        // set the initial balance of the reward token for the accumulator
        deal(address(rewardToken), address(baseAccumulator), initialBalance);
    }

    /// @notice Calculate the expected charged fee
    /// @param amount the amount to charge the fee for
    /// @return expectedChargedFee the expected charged fee
    function _calculateExpectedChargedFee(uint256 amount) internal view returns (uint256 expectedChargedFee) {
        AccumulatorBase.Split[] memory splits = baseAccumulator.getFeeSplit();

        // sum the fees sent to the fee receivers
        for (uint256 i; i < splits.length; i++) {
            expectedChargedFee += amount * splits[i].fee / 1e18;
        }

        // sum the claimer fee
        expectedChargedFee += amount * baseAccumulator.claimerFee() / 1e18;
    }

    function test_Returns0IfTheAmountIsZero() external {
        // it returns 0 if the amount is zero

        assertEq(baseAccumulator._expose_chargeFee(address(rewardToken), 0), 0);
    }

    function test_Returns0IfTheTokenIsNotTheRewardToken(address token) external {
        // it returns 0 if the token is not the reward token

        vm.assume(token != address(rewardToken));

        assertEq(baseAccumulator._expose_chargeFee(token, 100), 0);
    }

    function test_TransfersTheFeeToTheFeeReceivers(uint256 amount) external {
        // it transfers the fee to the fee receivers

        // assume the amount is greater than 1e18 and less than the initial balance
        vm.assume(amount > 1e18 && amount < initialBalance);

        // assert that the fee receivers have no initial balance
        AccumulatorBase.Split[] memory splits = baseAccumulator.getFeeSplit();
        for (uint256 i; i < splits.length; i++) {
            assertEq(ERC20(address(rewardToken)).balanceOf(splits[i].receiver), 0);
        }

        // charge the fee
        baseAccumulator._expose_chargeFee(address(rewardToken), amount);

        // assert that the fee receivers received the correct balance
        for (uint256 i; i < splits.length; i++) {
            assertEq(ERC20(address(rewardToken)).balanceOf(splits[i].receiver), amount * splits[i].fee / 1e18);
        }
    }

    function test_TransfersTheClaimerFeeToTheCaller(address caller, uint256 amount) external {
        // it transfers the claimer fee to the caller

        // assume the amount is greater than 1e18 and less than the initial balance
        vm.assume(amount > 1e18 && amount < initialBalance);
        vm.assume(caller != address(0));

        assertEq(ERC20(address(rewardToken)).balanceOf(caller), 0);

        // charge the fee
        vm.prank(caller);
        baseAccumulator._expose_chargeFee(address(rewardToken), amount);

        // assert that the caller received the correct balance
        assertEq(ERC20(address(rewardToken)).balanceOf(caller), amount * baseAccumulator.claimerFee() / 1e18);
    }

    function test_ReturnsTheAmountCharged(uint256 amount) external {
        // it returns the amount charged

        // assume the amount is greater than 1e18 and less than the initial balance
        vm.assume(amount > 1e18 && amount < initialBalance);

        // calculate the expected charged fee
        uint256 expectedChargedFee = _calculateExpectedChargedFee(amount);

        // assert that the amount charged is the expected amount
        assertEq(baseAccumulator._expose_chargeFee(address(rewardToken), amount), expectedChargedFee);
    }

    function test_EmitsSeveralFeeTransferredEvents(address caller, uint256 amount) external {
        // it emits several FeeTransferred events

        // assume the amount is greater than 1e18 and less than the initial balance
        vm.assume(amount > 1e18 && amount < initialBalance);

        AccumulatorBase.Split[] memory splits = baseAccumulator.getFeeSplit();

        // expect the fee to be transferred to the fee receivers
        for (uint256 i; i < splits.length; i++) {
            vm.expectEmit();
            emit FeeTransferred(splits[i].receiver, amount * splits[i].fee / 1e18, false);
        }

        // expect the claimer fee to be transferred to the caller
        vm.expectEmit();
        emit FeeTransferred(caller, amount * baseAccumulator.claimerFee() / 1e18, true);

        // charge the fee
        vm.prank(caller);
        baseAccumulator._expose_chargeFee(address(rewardToken), amount);
    }

    /// @notice Event emitted when the fee is sent to the fee receiver
    event FeeTransferred(address indexed receiver, uint256 amount, bool indexed isClaimerFee);
}
