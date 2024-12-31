// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IAccountant {
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint256 amount,
        bool softCheckpoint,
        uint256 pendingRewards
    ) external;
}
