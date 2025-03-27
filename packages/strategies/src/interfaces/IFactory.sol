// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IProtocolContext} from "./IProtocolContext.sol";

/// @title IFactory - Interface for Protocol-Specific Vault Factories
/// @notice Interface for the base factory contract that implements protocol-specific vault factories
/// @dev Defines core functionality for creating and managing vaults across different protocols
interface IFactory is IProtocolContext {
    function REWARD_VAULT_IMPLEMENTATION() external view returns (address);
    function REWARD_RECEIVER_IMPLEMENTATION() external view returns (address);
    function createVault(address gauge) external returns (address vault, address rewardReceiver);
    function syncRewardTokens(address gauge) external;
}
