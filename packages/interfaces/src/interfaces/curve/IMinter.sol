/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface IMinter {
    function mint(address gauge, address account, uint256 amount) external;
    function minted(address gauge, address account) external view returns (uint256);
}
