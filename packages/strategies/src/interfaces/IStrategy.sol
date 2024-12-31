// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IStrategy {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}
