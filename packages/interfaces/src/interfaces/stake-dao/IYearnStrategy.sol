// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IYearnStrategy {
    function claimDYFIRewardPool() external;
    function claimNativeRewards() external;
    function locker() external returns (address);
    function setAccumulator(address _accumulator) external;
}
