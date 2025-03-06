// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IRewardVault {
    function addRewardToken(address _rewardsToken, address _distributor) external;
    function depositRewards(address _rewardsToken, uint256 _amount) external;
    function isRewardToken(address _token) external view returns (bool);
    function getRewardTokens() external view returns (address[] memory);
}
