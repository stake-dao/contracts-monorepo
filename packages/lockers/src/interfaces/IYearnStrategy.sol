// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IYearnStrategy {
    function claimDYFIRewardPool() external;
    function claimNativeRewards() external;
    function locker() external returns (address);
    function setAccumulator(address _accumulator) external;
}
