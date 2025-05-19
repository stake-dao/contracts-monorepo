// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ISpectraRewardsDistributor {
    function claim(uint256 _tokenId) external returns (uint256);
    function claimable(uint256 _tokenId) external view returns (uint256);
    function checkpointToken() external;
    function authority() external view returns (address);
}
