// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ISpectraVoter {
    function reset(address _ve, uint256 _tokenId) external;
}