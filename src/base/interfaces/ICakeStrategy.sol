// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ICakeStrategy {
    function harvestNftAll(uint256 _tokenId) external;
}
