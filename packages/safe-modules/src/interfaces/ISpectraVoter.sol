// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ISpectraVoter {
    function length() external view returns(uint256);
    function poolIds(uint256 poolId) external view returns(uint160);
    function poolToBribe(uint160 poolId) external view returns(address);
    function poolToFees(uint160 poolId) external view returns(address);
}