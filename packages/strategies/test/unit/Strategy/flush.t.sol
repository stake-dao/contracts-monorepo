// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Strategy__flush is StrategyBaseTest {
    uint256 internal flushAmount = 1000 ether;

    function setUp() public override {
        super.setUp();
    }

    function test_RevertsIfNotCalledByAccountant() public {
        vm.prank(makeAddr("not_accountant"));

        vm.expectRevert(abi.encodeWithSignature("OnlyAccountant()"));
        strategy.flush();
    }

    function test_CorrectlyRetrievesFlushAmountFromTransientStorage() public {
        /// Set the flush amount in transient storage.
        strategy._cheat_setFlushAmount(flushAmount);

        /// Assert the flush amount is set in transient storage.
        assertEq(strategy.exposed_getFlushAmount(), flushAmount);
    }

    /// Transfer event.
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_CorrectlyExecutesTransferTransaction() public {
        /// Set the flush amount
        strategy._cheat_setFlushAmount(flushAmount);

        /// Mint the flush amount to the locker.
        rewardToken.mint(address(locker), flushAmount);

        // 1. It calls transfer on the reward token
        // 2. It transfers the flush amount to the accountant address
        // 3. It transfers the correct amount to the accountant address
        vm.expectEmit(true, true, true, true);
        emit Transfer({from: address(locker), to: address(accountant), value: flushAmount});

        /// Assert the flush amount is set before calling flush
        assertEq(strategy.exposed_getFlushAmount(), flushAmount);

        vm.prank(accountant);
        strategy.flush();

        /// Assert the flush amount is reset after calling flush
        assertEq(strategy.exposed_getFlushAmount(), 0);
        assertEq(rewardToken.balanceOf(address(accountant)), flushAmount);
    }
}
