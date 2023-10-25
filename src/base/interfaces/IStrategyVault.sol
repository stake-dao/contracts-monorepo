// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategyVault {
    function init() external;

    function transferGovernance(address _governance) external;

    function setLiquidityGauge(address _gauge) external;
}
