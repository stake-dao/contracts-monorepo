// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {BaseDepositorTest} from "./utils/BaseDepositorTest.t.sol";

contract BaseDepositor__shutdown is BaseDepositorTest {
    function test_SetsTheStateToCANCELED() external {
        // it sets the state to CANCELED

        assertEq(uint256(baseDepositor.state()), uint256(BaseDepositor.STATE.ACTIVE));

        vm.prank(governance);
        baseDepositor.shutdown();

        assertEq(uint256(baseDepositor.state()), uint256(BaseDepositor.STATE.CANCELED));
    }

    function test_EmitsTheStateUpdatedEvent() external {
        // it emits the StateUpdated event

        vm.expectEmit(true, true, true, true);
        emit StateUpdated(BaseDepositor.STATE.CANCELED);

        vm.prank(governance);
        baseDepositor.shutdown();
    }

    event StateUpdated(BaseDepositor.STATE newState);

    function test_TransferTheBalanceToTheGivenReceiver(uint256 balance, address receiver) external {
        // it transfer the balance to the given receiver

        vm.assume(balance > 0);
        vm.assume(receiver != address(0));
        deal(address(token), address(baseDepositor), balance);

        assertEq(IERC20(token).balanceOf(receiver), 0);
        assertEq(IERC20(token).balanceOf(address(baseDepositor)), balance);

        vm.prank(governance);
        baseDepositor.shutdown(receiver);

        assertEq(IERC20(token).balanceOf(receiver), balance);
        assertEq(IERC20(token).balanceOf(address(baseDepositor)), 0);
    }

    function test_TransferTheBalanceToTheGovernanceWhenNoReceiver(uint256 balance) external {
        // it transfer the balance to the governance when no receiver

        vm.assume(balance > 0);

        deal(address(token), address(baseDepositor), balance);

        assertEq(IERC20(token).balanceOf(governance), 0);
        assertEq(IERC20(token).balanceOf(address(baseDepositor)), balance);

        vm.prank(governance);
        baseDepositor.shutdown();

        assertEq(IERC20(token).balanceOf(governance), balance);
        assertEq(IERC20(token).balanceOf(address(baseDepositor)), 0);
    }

    function test_RevertsIfTheCallerIsNotTheGovernance() external {
        // it reverts if the caller is not the governance

        vm.expectRevert(BaseDepositor.GOVERNANCE.selector);
        baseDepositor.shutdown();
    }
}
