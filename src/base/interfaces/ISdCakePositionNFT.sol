// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ISdCakePositionNFT {
    function burn(uint256 id) external;
    function mint(address to, uint256 id) external;
    function ownerOf(uint256 id) external view returns (address);
}
