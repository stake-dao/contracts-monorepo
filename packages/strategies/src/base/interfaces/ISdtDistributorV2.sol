// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface ISdtDistributorV2 {
    function approveGauge(address _gauge) external;

    function distribute(address gauge) external;

    function initializeMasterchef(uint256) external;

    function masterchefToken() external view returns (address);

    function setDistribution(bool) external;
}
