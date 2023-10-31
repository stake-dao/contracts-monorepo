// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/base/strategy/Strategy.sol";
import "src/base/vault/StrategyVaultImpl.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

abstract contract StrategyTest is Test {
    using FixedPointMathLib for uint256;

    address public constant claimer = address(0xBEEC);

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
        address rewardToken = strategy.rewardToken();
        address rewardDistributor = strategy.rewardDistributors(address(strategy.gauges(address(vault.token()))));
        /// Before the harvest.
        uint256 _expectedLockerRewardTokenAmount = _getRewardTokenAmount(strategy);

        _;

        uint256 _claimerFee;
        uint256 _protocolFee;

        /// Compute the fees.
        _protocolFee = _expectedLockerRewardTokenAmount.mulDiv(17, 100);
        _expectedLockerRewardTokenAmount -= _protocolFee;

        _claimerFee = _expectedLockerRewardTokenAmount.mulDiv(1, 100);
        _expectedLockerRewardTokenAmount -= _claimerFee;

        assertEq(_balanceOf(rewardToken, address(claimer)), _claimerFee);

        assertEq(strategy.feesAccrued(), _protocolFee);
        assertEq(_balanceOf(rewardToken, address(strategy)), _protocolFee);

        uint256 _balanceRewardToken = _balanceOf(rewardToken, address(rewardDistributor));

        assertEq(_balanceRewardToken, _expectedLockerRewardTokenAmount);
    }

    modifier testFeeAccounting(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }

    function _getRewardTokenAmount(Strategy) internal virtual returns (uint256) {
        return 0;
    }

    function _getExtraRewardTokenAmount(Strategy) internal virtual returns (uint256) {
        return 0;
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }
}
