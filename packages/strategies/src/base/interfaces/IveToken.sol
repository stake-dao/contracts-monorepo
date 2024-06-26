// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IveToken {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    function admin() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    function locked(address) external view returns (LockedBalance memory);
}
