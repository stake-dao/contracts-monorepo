// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ISpectraVoter {
    function reset(address _ve, uint256 _tokenId) external;
    function length() external view returns (uint256);
    function poolIds(uint256 poolId) external view returns (uint160);
    function poolToBribe(uint160 poolId) external view returns (address);
    function poolToFees(uint160 poolId) external view returns (address);
}
