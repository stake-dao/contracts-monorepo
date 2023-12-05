// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IRevenueSharingPool {
    function checkpointToken() external;
    function rewardToken() external returns (address);
    function balanceOfAtUser(address _user, uint256 _ts) external view returns (uint256);
    function tokensPerWeek(uint256 _period) external view returns (uint256);
}
