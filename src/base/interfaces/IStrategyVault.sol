// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategyVault {
    function init(address _lp, address _governance, string memory name, string memory symbol, address strategy)
        external;

    function setGovernance(address _governance) external;

    function setLiquidityGauge(address _gauge) external;
}
