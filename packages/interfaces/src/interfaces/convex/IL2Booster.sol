/// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IL2Booster {

    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, address gauge, address rewards, bool shutdown, address factory);

    function deposit(uint256 _pid, uint256 _amount) external returns (bool);

}