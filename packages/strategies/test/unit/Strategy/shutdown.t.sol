// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {Strategy, IStrategy} from "src/Strategy.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";

contract Strategy__shutdown is StrategyBaseTest {
    function test_RevertCallerNotAllowed() public {
        address notAllowed = makeAddr("notAllowed");

        /// Caller is not allowed.
        assertFalse(registry.allowed(notAllowed, gauge, Strategy.shutdown.selector));

        /// Gauge is not shutdown.
        assertFalse(registry.isShutdown(gauge));

        vm.prank(notAllowed);
        vm.expectRevert(abi.encodeWithSelector(Strategy.OnlyProtocolController.selector));
        strategy.shutdown(gauge);
    }

    function test_RevertAllowedCallerNotShutdown() public {
        /// Cheat the locker balance to avoid reverting on shutdown.
        stakingToken.mint(address(locker), 100);


        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(stakingToken)));


        /// Gauge is not shutdown.
        assertFalse(registry.isShutdown(gauge));

        vm.prank(address(registry));
        strategy.shutdown(gauge);
    }

    event Shutdown(address indexed gauge);


    function test_Shutdown() public {
        /// Cheat the sidecar balances
        stakingToken.mint(address(locker), 100);
        stakingToken.mint(address(sidecar1), 200);
        stakingToken.mint(address(sidecar2), 300);

        vm.prank(vault);
        strategy.deposit(allocation, IStrategy.HarvestPolicy.CHECKPOINT);
        assertEq(strategy.balanceOf(gauge), 600);



        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(stakingToken)));

        vm.prank(address(registry));
        strategy.shutdown(gauge);

        assertEq(strategy.balanceOf(gauge), 0);
        assertEq(stakingToken.balanceOf(address(vault)), 600);
    }
}
