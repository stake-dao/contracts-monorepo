// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

interface IVeYFI {
    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    function balanceOf(address account) external view returns (uint256);

    function withdraw() external;

    function locked(address) external view returns (LockedBalance memory);

    function modify_lock(uint256 amount, uint256 unlock_time) external;
}
