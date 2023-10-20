// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategy {
    function feeReceiver() external view returns (address);

    function gauges(address _lp) external view returns (address);

    function locker() external view returns(address);

    function protocolFeesPercent() external view returns (uint256);

    function rewardDistributors(address _gauge) external view returns (address);

    function setGauge(address _lp, address _gauge) external;

    function setRewardDistributor(address _gauge, address _distributor) external;

    function toggleVault(address _vault) external;

    function withdraw(address _token, uint256 _amount, address _to) external;
}
