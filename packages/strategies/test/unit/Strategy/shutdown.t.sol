// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {Strategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";

contract Strategy__shutdown is StrategyBaseTest {
    function test_RevertCallerNotAllowed() public {
        address notAllowed = makeAddr("notAllowed");

        /// Caller is not allowed.
        assertFalse(registry.allowed(notAllowed, gauge, Strategy.shutdown.selector));

        /// Gauge is not shutdown.
        assertFalse(registry.isShutdown(gauge));

        vm.prank(notAllowed);
        vm.expectRevert(abi.encodeWithSelector(Strategy.OnlyAllowed.selector));
        strategy.shutdown(gauge);
    }

    function test_RevertAllowedCallerNotShutdown() public {
        /// Cheat the locker balance to avoid reverting on shutdown.
        stakingToken.mint(address(locker), 100);

        address allowedCaller = makeAddr("allowedCaller");
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(
                IProtocolController.allowed.selector, address(strategy), allowedCaller, Strategy.shutdown.selector
            ),
            abi.encode(true)
        );

        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(stakingToken)));

        /// Caller is allowed.
        assertTrue(registry.allowed(address(strategy), allowedCaller, Strategy.shutdown.selector));

        /// Gauge is not shutdown.
        assertFalse(registry.isShutdown(gauge));

        vm.prank(allowedCaller);
        strategy.shutdown(gauge);
    }

    event Shutdown(address indexed gauge);

    function test_shutownWithCallerNotAllowedAndGaugeShutdown() public {
        /// Cheat the locker balance to avoid reverting on shutdown.
        stakingToken.mint(address(locker), 100);

        address notAllowedCaller = makeAddr("notAllowedCaller");

        /// Caller is not allowed.
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(
                IProtocolController.allowed.selector, address(strategy), notAllowedCaller, Strategy.shutdown.selector
            ),
            abi.encode(false)
        );

        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(stakingToken)));

        /// But gauge is shutdown.
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.isShutdown.selector, gauge), abi.encode(true)
        );

        vm.expectEmit();
        emit Shutdown(gauge);

        /// So the function become permissionless.
        vm.prank(notAllowedCaller);
        strategy.shutdown(gauge);
    }

    function test_RevertAlreadyShutdown() public {
        vm.mockCall(
            address(registry), abi.encodeWithSelector(IProtocolController.isShutdown.selector, gauge), abi.encode(true)
        );

        vm.expectRevert(abi.encodeWithSelector(Strategy.AlreadyShutdown.selector));
        strategy.shutdown(gauge);
    }

    function test_Shutdown() public {
        /// Cheat the sidecar balances
        stakingToken.mint(address(locker), 100);
        stakingToken.mint(address(sidecar1), 200);
        stakingToken.mint(address(sidecar2), 300);

        vm.prank(vault);
        strategy.deposit(allocation, false);
        assertEq(strategy.balanceOf(gauge), 600);

        address allowedCaller = makeAddr("allowedCaller");

        /// Caller is not allowed.
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(
                IProtocolController.allowed.selector, address(strategy), allowedCaller, Strategy.shutdown.selector
            ),
            abi.encode(true)
        );

        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(stakingToken)));

        assertTrue(registry.allowed(address(strategy), allowedCaller, Strategy.shutdown.selector));

        vm.prank(allowedCaller);
        strategy.shutdown(gauge);

        assertEq(strategy.balanceOf(gauge), 0);
        assertEq(stakingToken.balanceOf(address(vault)), 600);
    }
}
