// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IPendleGauge {
    struct RewardState {
        uint128 index;
        uint128 lastBalance;
    }

    struct UserReward {
        uint128 index;
        uint128 accrued;
    }

    function totalActiveSupply() external view returns (uint256);
    function activeBalance(address user) external view returns (uint256);
    function userReward(address token, address user) external view returns (UserReward memory);
    function rewardState(address token) external view returns (RewardState memory);
    function readTokens() external view returns (address sy, address pt, address yt);
}
