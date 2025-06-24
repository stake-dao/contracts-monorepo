// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IYieldNest {
    struct LockedBalance {
        uint208 amount;
        uint48 start; // mirrors oz ERC20 timestamp clocks
    }

    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function createLock(uint256 amount) external returns (uint256 tokenId);
    function votingPowerForAccount(address account) external view returns (uint256);
    function lastLockId() external view returns (uint256);
}
