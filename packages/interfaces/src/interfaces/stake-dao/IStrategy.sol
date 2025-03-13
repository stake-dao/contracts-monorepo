// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IStrategy {
    function locker() external view returns (address);

    function deposit(address _token, uint256 amount) external;
    function withdraw(address _token, uint256 amount) external;

    function claimProtocolFees() external;
    function claimNativeRewards() external;
    function harvest(address _asset, bool _distributeSDT, bool _claimExtra) external;

    function rewardDistributors(address _gauge) external view returns (address);
    function isShutdown(address _gauge) external view returns (bool);

    /// Factory functions
    function toggleVault(address vault) external;
    function setGauge(address token, address gauge) external;
    function setLGtype(address gauge, uint256 gaugeType) external;
    function addRewardToken(address _token, address _rewardDistributor) external;
    function acceptRewardDistributorOwnership(address rewardDistributor) external;
    function setRewardDistributor(address gauge, address rewardDistributor) external;
    function addRewardReceiver(address gauge, address rewardReceiver) external;

    // Governance 
    function setAccumulator(address newAccumulator) external;
    function setFeeRewardToken(address newFeeRewardToken) external;
    function setFeeDistributor(address newFeeDistributor) external;
    function setFactory(address newFactory) external;
}
