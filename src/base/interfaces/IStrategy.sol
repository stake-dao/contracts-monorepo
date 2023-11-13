// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategy {
    function addRewardToken(address _token, address _distributor) external;

    function acceptRewardDistributorOwnership(address _rewardDistributor) external;

    function deposit(address _token, uint256 _amount) external;

    function feeReceiver() external view returns (address);

    function execute(address _to, uint256 _value, bytes memory _data)
        external
        returns (bool _success, bytes memory _result);

    function gauges(address _lp) external view returns (address);

    function locker() external view returns (address);

    function protocolFeesPercent() external view returns (uint256);

    function rewardDistributors(address _gauge) external view returns (address);

    function setGauge(address _lp, address _gauge) external;

    function setRewardDistributor(address _gauge, address _distributor) external;

    function toggleVault(address _vault) external;

    function withdraw(address _token, uint256 _amount) external;

    function setLGtype(address _gauge, uint256 _type) external;

    function setRewardReceiver(address _gauge, address _rewardReceiver) external;
}
