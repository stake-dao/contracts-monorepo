// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IPendleGauge {
    function totalActiveSupply() external view returns (uint256);
    function activeBalance(address user) external view returns (uint256);
    function userReward(address token, address user) external view returns (uint128 index, uint128 accrued);
}
