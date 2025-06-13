// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IL2BaseRewardPool {

    struct RewardType {
        address rewardToken;
        uint256 rewardIntegral;
        uint256 rewardRemaining;
    }

    function getReward(address _account) external returns (bool);
    function withdraw(uint256 amount, bool claim) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
    function earned(address _account) external returns (uint256);
    function rewardLength() external view returns (uint256);
    function rewards(uint256 index) external view returns (RewardType memory);
}