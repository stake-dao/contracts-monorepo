// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IPendleMarket {
    function redeemRewards(address user) external;
    function getRewardTokens() external returns (address[] memory);
}
