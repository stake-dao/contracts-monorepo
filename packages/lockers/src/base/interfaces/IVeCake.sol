// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IVeCake {
    function createLock(uint256 _amount, uint256 _unlockTime) external;

    function withdrawAll(address _to) external;

    function getUserInfo(address _user)
        external
        view
        returns (
            int128 amount,
            uint256 end,
            address cakePoolProxy,
            uint128 cakeAmount,
            uint48 lockEndTime,
            uint48 migrationTime,
            uint16 cakePoolType,
            uint16 withdrawFlag
        );

    function increaseLockAmount(uint256 _amount) external;

    function increaseUnlockTime(uint256 _unlockTime) external;
}
