// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/base/strategy/Strategy.sol";
import "src/base/vault/StrategyVaultImpl.sol";

abstract contract StrategyTest is Test {
    modifier testDeposit(StrategyVaultImpl vault, Strategy strategy, uint256 amount) {
        _;
        ERC20 token = vault.token();
        address locker = address(strategy.locker());
        address gauge = strategy.gauges(address(token));
        address rewardDistributor = strategy.rewardDistributors(address(gauge));

        /// Token Balances.
        assertEq(token.balanceOf(locker), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);

        /// Strategy Balances.
        assertEq(strategy.balanceOf(address(token)), amount);

        /// Gauge Balances.
        assertEq(ILiquidityGauge(gauge).balanceOf(locker), amount);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(ILiquidityGauge(rewardDistributor).balanceOf(address(this)), amount);
    }

    modifier testWithdraw(StrategyVaultImpl vault, Strategy strategy, uint256 amount) {
        _;

        ERC20 token = vault.token();
        address locker = address(strategy.locker());
        address gauge = strategy.gauges(address(token));
        address rewardDistributor = strategy.rewardDistributors(address(gauge));

        /// Token Balances.
        assertEq(token.balanceOf(locker), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        /// Strategy Balances.
        assertEq(strategy.balanceOf(address(token)), 0);

        /// Gauge Balances.
        assertEq(ILiquidityGauge(gauge).balanceOf(locker), 0);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(ILiquidityGauge(rewardDistributor).balanceOf(address(this)), 0);
    }

    modifier _testHarvest(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }

    modifier testFeeAccounting(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }
}
