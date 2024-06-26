// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IMc {
    function add(uint256, address, bool) external;

    function owner() external view returns (address);

    function poolLength() external view returns (uint256);
}
