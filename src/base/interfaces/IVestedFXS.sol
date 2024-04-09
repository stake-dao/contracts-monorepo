// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface IVestedFXS {
    function balanceOf(address _addr) external view returns (uint256);

    function createLock(address _addr, uint256 _value, uint128 _unlockTime)
        external
        returns (uint128 index_, uint256 newLockId_);

    function increaseAmount(uint256 _value, uint128 _lockIndex) external;

    function increaseUnlockTime(uint128 _unlockTime, uint128 _lockIndex) external;

    function lockedEnd(address _addr, uint128 _lockIndex) external view returns (uint256);

    function nextId(address _addr) external view returns (uint256);

    function withdraw(uint128 _lockIndex) external;
}
