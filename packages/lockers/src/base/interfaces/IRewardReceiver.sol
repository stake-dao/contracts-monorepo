// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IRewardReceiver {
    function split() external;
    function accumulatorRewardToken(address) external view returns (address);
}
