// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IYearnStrategy {
    function claimDYFIRewardPool() external;
    function claimNativeRewards() external;
    function locker() external returns (address);
    function setAccumulator(address _accumulator) external;
}
