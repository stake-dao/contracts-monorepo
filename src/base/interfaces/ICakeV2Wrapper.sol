// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ICakeV2Wrapper {
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt;
        uint256 boostMultiplier; // currently active multiplier
        uint256 boostedAmount; // combined boosted amount
        uint256 unsettledRewards; // rewards haven't been transferred to users but already accounted in rewardDebt
    }

    function deposit(uint256 _amount, bool _noHarvest) external;

    function stakedToken() external view returns (address);

    function userInfo(address _user) external view returns (UserInfo memory);

    function adapterAddr() external view returns (address);

    function depositRewardAndExpend(uint256 _amount) external;

    function updateStartAndEndTimestamp(uint256 _startTimestamp, uint256 _endTimestamp) external;
    function restart(uint256 _startTimestamp, uint256 _endTimestamp, uint256 _rewardPerSecond) external;

    function owner() external view returns (address);

    function endTimestamp() external view returns (uint256);
}
