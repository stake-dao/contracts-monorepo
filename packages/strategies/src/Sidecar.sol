// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Sidecar - Abstract Base Sidecar Contract
/// @notice A base contract for implementing protocol-specific sidecars
/// @dev Provides core functionality for protocol-specific sidecar implementations
///      Key responsibilities:
///      - Handles deposits and withdrawals through protocol-specific implementations
///      - Manages protocol-specific reward claiming
///      - Provides access control for strategy and accountant interactions
abstract contract Sidecar is ISidecar {
    using SafeERC20 for IERC20;

    /// @notice The protocol ID.
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The accountant address.
    address public immutable ACCOUNTANT;

    /// @notice The protocol controller address.
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when caller is not strategy
    error OnlyStrategy();

    /// @notice Error emitted when caller is not accountant
    error OnlyAccountant();

    /// @notice Error emitted when contract is not initialized
    error AlreadyInitialized();

    /// @notice Error emitted when zero address is provided
    error ZeroAddress();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Ensures the caller is the accountant
    modifier onlyAccountant() {
        require(msg.sender == ACCOUNTANT, OnlyAccountant());
        _;
    }

    /// @notice Ensures the caller is the strategy registered for the protocol
    modifier onlyStrategy() {
        require(msg.sender == PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID), OnlyStrategy());
        _;
    }

    //////////////////////////////////////////////////////
    /// --- ISIDECAR IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the Minimal Proxy Factory.
    function factory() public view virtual returns (ISidecarFactory);

    /// @notice Staking token address.
    function asset() public view virtual returns (IERC20);

    /// @notice Reward token address.
    function rewardToken() public view virtual returns (IERC20);

    /// @notice Reward receiver address.
    function rewardReceiver() public view virtual returns (address);

    //////////////////////////////////////////////////////
    /// --- INITIALIZATION
    //////////////////////////////////////////////////////

    /// @notice Initialize the contract
    /// @dev Must be implemented by derived sidecars to handle protocol-specific initialization
    function initialize() external virtual;

    //////////////////////////////////////////////////////
    /// --- ISIDECAR OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Deposit tokens into the protocol
    /// @param amount Amount of tokens to deposit
    /// @dev Only callable by the strategy
    function deposit(uint256 amount) external virtual;

    /// @notice Withdraw tokens from the protocol
    /// @param amount Amount of tokens to withdraw
    /// @param receiver Address to receive the tokens
    /// @dev Only callable by the strategy
    function withdraw(uint256 amount, address receiver) external virtual;

    /// @notice Claim rewards from the protocol
    /// @return Amount of reward token claimed
    /// @dev Only callable by the accountant
    function claim() external virtual returns (uint256);

    /// @notice Get the balance of tokens in the protocol
    /// @return The balance of tokens
    function balanceOf() public view virtual returns (uint256);

    /// @notice Get the amount of pending rewards
    /// @return The amount of pending rewards
    function getPendingRewards() public view virtual returns (uint256);

    /// @notice Get the reward tokens from the protocol
    /// @return Array of reward token addresses
    function getRewardTokens() public view virtual returns (address[] memory);
}
