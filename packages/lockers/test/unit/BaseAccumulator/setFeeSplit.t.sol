// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__setFeeSplit is BaseAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        baseAccumulator.setFeeSplit(new BaseAccumulator.Split[](0));
    }

    function test_RevertsIfTheSplitsAreEmpty() external {
        // it reverts if the splits are empty

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(BaseAccumulator.INVALID_SPLIT.selector);
        baseAccumulator.setFeeSplit(new BaseAccumulator.Split[](0));
    }

    function test_RevertsIfTheTotalFeesAreGreaterThanTheDenominator() external {
        // it reverts if the total fees are greater than the denominator

        uint256 denominator = baseAccumulator.DENOMINATOR();

        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](3);
        splits[0] = BaseAccumulator.Split({receiver: makeAddr("receiver1"), fee: uint96(denominator / 2)});
        splits[1] = BaseAccumulator.Split({receiver: makeAddr("receiver2"), fee: uint96(denominator / 2)});
        splits[2] = BaseAccumulator.Split({receiver: makeAddr("receiver3"), fee: uint96(denominator / 2)});

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(BaseAccumulator.FEE_TOO_HIGH.selector);
        baseAccumulator.setFeeSplit(splits);
    }

    function test_RevertsIfOneOfTheReceiversIsTheZeroAddress() external {
        // it reverts if one of the receivers is the zero address

        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](3);
        splits[0] = BaseAccumulator.Split({receiver: makeAddr("receiver1"), fee: 100});
        splits[1] = BaseAccumulator.Split({receiver: address(0), fee: 100});
        splits[2] = BaseAccumulator.Split({receiver: makeAddr("receiver3"), fee: 100});

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        baseAccumulator.setFeeSplit(splits);
    }

    function test_SetsTheFeeSplits() external {
        // it sets the fee splits
        uint256 denominator = baseAccumulator.DENOMINATOR();

        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](3);
        splits[0] = BaseAccumulator.Split({receiver: makeAddr("receiver1"), fee: uint96(denominator / 4)});
        splits[1] = BaseAccumulator.Split({receiver: makeAddr("receiver2"), fee: uint96(denominator / 4)});
        splits[2] = BaseAccumulator.Split({receiver: makeAddr("receiver3"), fee: uint96(denominator / 4)});

        vm.prank(baseAccumulator.governance());
        baseAccumulator.setFeeSplit(splits);

        BaseAccumulator.Split[] memory newSplits = baseAccumulator.getFeeSplit();

        assertEq(newSplits.length, 3);
        for (uint256 i = 0; i < newSplits.length; i++) {
            assertEq(newSplits[i].receiver, splits[i].receiver);
            assertEq(newSplits[i].fee, splits[i].fee);
        }
    }

    function test_EmitsAEvent() external {
        // it emits a event

        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](3);
        splits[0] = BaseAccumulator.Split({receiver: makeAddr("receiver1"), fee: 1e14});
        splits[1] = BaseAccumulator.Split({receiver: makeAddr("receiver2"), fee: 5e15});
        splits[2] = BaseAccumulator.Split({receiver: makeAddr("receiver3"), fee: 1e15});

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit FeeSplitUpdated(splits);
        baseAccumulator.setFeeSplit(splits);
    }

    /// @notice Event emitted when the fee split is updated
    event FeeSplitUpdated(BaseAccumulator.Split[] splits);
}
