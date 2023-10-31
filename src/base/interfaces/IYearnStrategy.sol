// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IYearnStrategy {
    function claimDYfiRewardPool() external;
    function locker() external returns(address);
}