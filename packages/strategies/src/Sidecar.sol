// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";

/// @title Sidecar - Abstract Base Sidecar Contract
/// @notice A base contract for implementing protocol-specific sidecars
/// @dev Provides core functionality for depositing, withdrawing, and managing assets across different protocols
abstract contract Sidecar is ISidecar {
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The protocol identifier
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The accountant contract address
    address public immutable ACCOUNTANT;

    /// @notice The reward token address
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The protocol controller contract
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    /// --- STORAGE
    //////////////////////////////////////////////////////

    /// @notice Whether the sidecar has been initialized
    bool private _initialized;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the strategy
    error OnlyStrategy();

    /// @notice Error thrown when the caller is not the accountant
    error OnlyAccountant();

    /// @notice Error thrown when the sidecar is already initialized
    error AlreadyInitialized();

    /// @notice Error thrown when the sidecar is not initialized
    error NotInitialized();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Ensures the caller is the strategy
    /// @custom:throws OnlyStrategy If the caller is not the strategy
    modifier onlyStrategy() {
        require(PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID) == msg.sender, OnlyStrategy());
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the sidecar with protocol ID, accountant, and protocol controller
    /// @param _protocolId The identifier for the protocol this sidecar interacts with
    /// @param _accountant The address of the accountant contract
    /// @param _protocolController The address of the protocol controller
    constructor(bytes4 _protocolId, address _accountant, address _protocolController) {
        PROTOCOL_ID = _protocolId;
        ACCOUNTANT = _accountant;
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
        REWARD_TOKEN = IERC20(IAccountant(_accountant).REWARD_TOKEN());

        _initialized = true;
    }

    //////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Initializes the sidecar
    /// @dev Can only be called once
    /// @custom:throws AlreadyInitialized If the sidecar is already initialized
    function initialize() external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _initialize();
    }

    /// @notice Deposits assets into the sidecar
    /// @param amount The amount to deposit
    /// @custom:throws OnlyStrategy If the caller is not the strategy
    function deposit(uint256 amount) external onlyStrategy {
        _deposit(amount);
    }

    /// @notice Withdraws assets from the sidecar
    /// @param amount The amount to withdraw
    /// @param receiver The address to receive the withdrawn assets
    /// @custom:throws OnlyStrategy If the caller is not the strategy
    function withdraw(uint256 amount, address receiver) external onlyStrategy {
        _withdraw(amount, receiver);
    }

    /// @notice Claims pending rewards from the sidecar
    /// @custom:throws OnlyAccountant If the caller is not the accountant
    function claim() external onlyStrategy returns (uint256) {
        return _claim();
    }

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Returns the asset of the sidecar
    /// @return The asset of the sidecar
    function asset() public view virtual returns (IERC20);

    /// @notice Returns the reward receiver of the sidecar
    /// @return The reward receiver of the sidecar
    function rewardReceiver() public view virtual returns (address);

    //////////////////////////////////////////////////////
    /// --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Initializes the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific initialization
    function _initialize() internal virtual;

    /// @notice Deposits assets into the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific deposits
    /// @param amount The amount to deposit
    function _deposit(uint256 amount) internal virtual;

    /// @notice Claims pending rewards from the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific claims
    function _claim() internal virtual returns (uint256);

    /// @notice Withdraws assets from the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific withdrawals
    /// @param amount The amount to withdraw
    /// @param receiver The address to receive the withdrawn assets
    function _withdraw(uint256 amount, address receiver) internal virtual;

    /// @notice Returns the balance of the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific balance calculation
    /// @return The balance of the sidecar
    function balanceOf() public view virtual returns (uint256);

    /// @notice Returns the pending rewards of the sidecar
    /// @dev Must be implemented by derived sidecars to handle protocol-specific reward calculation
    /// @return The pending rewards of the sidecar
    function getPendingRewards() public view virtual returns (uint256);
}
