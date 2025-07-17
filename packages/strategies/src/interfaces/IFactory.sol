// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IFactory {
    function createVault(address gauge) external returns (address vault, address rewardReceiver);
    function syncRewardTokens(address gauge) external;
}
