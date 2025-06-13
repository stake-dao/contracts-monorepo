// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IBaseRewardPool {
    function rewardToken() external view returns (address);
    function extraRewardsLength() external view returns (uint256);
    function extraRewards(uint256 index) external view returns (address);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
    function getReward(address _account, bool _claimExtras) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
    function earned(address _account) external view returns (uint256);
    function rewardRate() external view returns (uint256);
}