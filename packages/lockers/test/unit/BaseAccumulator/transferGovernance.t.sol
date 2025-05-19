// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__transferGovernance is BaseAccumulatorTest {
    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != address(baseAccumulator.governance()));

        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        baseAccumulator.transferGovernance(makeAddr("futureGovernance"));
    }

    function test_RevertsIfTheGivenFutureGovernanceIsTheZeroAddress() external {
        // it reverts if the given future governance is the zero address

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(BaseAccumulator.ZERO_ADDRESS.selector);
        baseAccumulator.transferGovernance(address(0));
    }

    function test_StoreTheFutureGovernance(address futureGovernance) external {
        // it store the future governance

        vm.assume(futureGovernance != address(0));

        vm.prank(baseAccumulator.governance());
        baseAccumulator.transferGovernance(futureGovernance);

        assertEq(baseAccumulator.futureGovernance(), futureGovernance);
    }

    function test_EmitsAEvent(address futureGovernance) external {
        // it emits a event

        vm.assume(futureGovernance != address(0));

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdateProposed(futureGovernance);
        baseAccumulator.transferGovernance(futureGovernance);
    }

    /// @notice Event emitted when the governance update is proposed
    event GovernanceUpdateProposed(address newFutureGovernance);
}
