// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IRewardReceiver {
    function split() external;
    function accumulatorRewardToken(address) external view returns (address);
}
