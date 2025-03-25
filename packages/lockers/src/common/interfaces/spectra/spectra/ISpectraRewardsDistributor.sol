// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ISpectraRewardsDistributor {
    function claim(uint256 _tokenId) external returns (uint256);
    function claimable(uint256 _tokenId) external view returns (uint256);
    function checkpointToken() external;
    function authority() external view returns (address);
}
