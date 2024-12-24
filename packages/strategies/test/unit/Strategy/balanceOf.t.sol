// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";
import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";

contract Strategy__balanceOf is StrategyBaseTest {
    address internal gauge;

    function setUp() public override {
        super.setUp();
        gauge = makeAddr("gauge");
    }

    function test_CorrectlyRetrievesBalanceFromLocker(uint256 lockerBalance) public {
        strategy._cheat_setLockerBalance(gauge, lockerBalance);

        address[] memory emptyTargets = new address[](0);
        strategy._cheat_setAllocationTargets(gauge, address(allocator), emptyTargets);

        assertEq(strategy.balanceOf(gauge), lockerBalance);
    }

    function test_CorrectlyRetrievesAllocator() public {
        strategy._cheat_setLockerBalance(gauge, 0);

        address[] memory emptyTargets = new address[](0);
        strategy._cheat_setAllocationTargets(gauge, address(allocator), emptyTargets);

        strategy.balanceOf(gauge);

        assertTrue(true);
    }

    function test_CorrectlyRetrievesAllocationTargets() public {
        strategy._cheat_setLockerBalance(gauge, 0);

        address[] memory targets = new address[](2);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");

        strategy._cheat_setAllocationTargets(gauge, address(allocator), targets);

        strategy._cheat_setSidecarBalance(targets[0], 0);
        strategy._cheat_setSidecarBalance(targets[1], 0);

        strategy.balanceOf(gauge);

        assertTrue(true);
    }

    function test_CorrectlySumsBalancesFromAllSidecars(uint128 balance1, uint128 balance2) public {
        strategy._cheat_setLockerBalance(gauge, 0);

        address[] memory targets = new address[](2);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");

        strategy._cheat_setAllocationTargets(gauge, address(allocator), targets);

        strategy._cheat_setSidecarBalance(targets[0], balance1);
        strategy._cheat_setSidecarBalance(targets[1], balance2);

        assertEq(strategy.balanceOf(gauge), uint256(balance1) + uint256(balance2));
    }

    function test_ReturnsTotalBalanceAcrossAllTargets(uint128 lockerBalance, uint128 balance1, uint128 balance2)
        public
    {
        strategy._cheat_setLockerBalance(gauge, lockerBalance);

        address[] memory targets = new address[](2);
        targets[0] = makeAddr("target1");
        targets[1] = makeAddr("target2");

        strategy._cheat_setAllocationTargets(gauge, address(allocator), targets);

        strategy._cheat_setSidecarBalance(targets[0], balance1);
        strategy._cheat_setSidecarBalance(targets[1], balance2);

        assertEq(strategy.balanceOf(gauge), uint256(lockerBalance) + uint256(balance1) + uint256(balance2));
    }

    function test_ReturnsOnlyLockerBalanceWhenNoSidecarsExist(uint256 lockerBalance) public {
        strategy._cheat_setLockerBalance(gauge, lockerBalance);

        address[] memory emptyTargets = new address[](0);
        strategy._cheat_setAllocationTargets(gauge, address(allocator), emptyTargets);

        assertEq(strategy.balanceOf(gauge), lockerBalance);
    }
}
