// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {BaseAccumulatorTest} from "test/unit/BaseAccumulator/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__approveNewTokenReward is BaseAccumulatorTest {
    MockERC20 internal newTokenReward;

    function setUp() public override {
        super.setUp();

        // deploy a new reward token
        newTokenReward = new MockERC20();
        newTokenReward.initialize("New Reward Token", "NRT", 18);
    }

    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        baseAccumulator.approveNewTokenReward(address(newTokenReward));
    }

    function test_SetMaxApprovalForTheNewTokenRewardToTheGauge() external {
        // it set max approval for the new token reward to the gauge

        assertEq(newTokenReward.allowance(address(baseAccumulator), address(gauge)), 0);

        vm.prank(baseAccumulator.governance());
        baseAccumulator.approveNewTokenReward(address(newTokenReward));

        assertEq(newTokenReward.allowance(address(baseAccumulator), address(gauge)), type(uint256).max);
    }

    function test_EmitsAEvent() external {
        // it emits a event

        vm.prank(baseAccumulator.governance());
        vm.expectEmit(true, true, true, true);
        emit RewardTokenApproved(address(newTokenReward));
        baseAccumulator.approveNewTokenReward(address(newTokenReward));
    }

    /// @notice Event emitted when the reward token is approved
    event RewardTokenApproved(address newRewardToken);
}
