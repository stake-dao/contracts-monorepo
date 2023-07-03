// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IPendleLocker {
    function createLock(uint256, uint256) external;

    function increaseAmount(uint128) external;

    function increaseUnlockTime(uint128) external;
}
