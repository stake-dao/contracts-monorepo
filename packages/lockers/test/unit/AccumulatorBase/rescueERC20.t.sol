// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {BaseAccumulatorTest} from "test/unit/AccumulatorBase/utils/BaseAccumulatorTest.sol";

contract BaseAccumulator__rescueERC20 is BaseAccumulatorTest {
    MockERC20 internal randomToken;
    uint256 internal balance = 1_000;

    function setUp() public override {
        super.setUp();

        // deploy a new token
        randomToken = new MockERC20();
        randomToken.initialize("Random Token", "RT", 18);

        // airdrop¡ some tokens to the accumulator
        deal(address(randomToken), address(baseAccumulator), balance);
    }

    function test_RevertsIfTheCallerIsNotTheGovernance(address caller) external {
        // it reverts if the caller is not the governance

        vm.assume(caller != baseAccumulator.governance());

        vm.prank(caller);
        vm.expectRevert(AccumulatorBase.GOVERNANCE.selector);
        baseAccumulator.rescueERC20(address(randomToken), 100, makeAddr("recipient"));
    }

    function test_RevertsIfTheRecipientIsTheZeroAddress() external {
        // it reverts if the recipient is the zero address

        vm.prank(baseAccumulator.governance());
        vm.expectRevert(AccumulatorBase.ZERO_ADDRESS.selector);
        baseAccumulator.rescueERC20(address(randomToken), 100, address(0));
    }

    function test_RevertsIfTheAmountExceedsTheBalance() external {
        // it reverts if the amount exceeds the balance

        vm.prank(baseAccumulator.governance());
        vm.expectRevert();
        baseAccumulator.rescueERC20(address(randomToken), balance + 1, makeAddr("recipient"));
    }

    function test_TransferTheHeldTokensToTheRecipient(uint256 amount, address recipient) external {
        // it transfer the held tokens to the recipient

        vm.assume(amount <= balance);
        vm.assume(recipient != address(0));

        vm.prank(baseAccumulator.governance());
        baseAccumulator.rescueERC20(address(randomToken), amount, recipient);

        assertEq(randomToken.balanceOf(recipient), amount);
        assertEq(randomToken.balanceOf(address(baseAccumulator)), balance - amount);
    }
}
