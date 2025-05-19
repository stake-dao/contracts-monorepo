// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__acceptGovernance is BaseAccumulatorTest {
    address internal futureGovernance;

    function setUp() public virtual override {
        super.setUp();

        futureGovernance = makeAddr("futureGovernance");
        vm.prank(baseAccumulator.governance());
        baseAccumulator.transferGovernance(futureGovernance);
    }

    function test_RevertsIfTheCallerIsNotTheFutureGovernance(address caller) external {
        // it reverts if the caller is not the future governance

        vm.assume(caller != futureGovernance);

        vm.prank(caller);
        vm.expectRevert(BaseAccumulator.FUTURE_GOVERNANCE.selector);
        baseAccumulator.acceptGovernance();
    }

    function test_SetsTheGovernanceToTheFutureGovernance() external {
        // it sets the governance to the future governance

        vm.prank(futureGovernance);
        baseAccumulator.acceptGovernance();

        assertEq(baseAccumulator.governance(), futureGovernance);
    }

    function test_EmitsAEvent() external {
        // it emits a event

        vm.prank(futureGovernance);
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdateAccepted(futureGovernance);
        baseAccumulator.acceptGovernance();
    }

    /// @notice Event emitted when the governance update is accepted
    event GovernanceUpdateAccepted(address newGovernance);
}
