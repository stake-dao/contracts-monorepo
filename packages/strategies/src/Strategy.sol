// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Strategy - Abstract Base Strategy Contract
/// @notice A base contract for implementing protocol-specific strategies
/// @dev Provides core functionality for depositing, withdrawing, and managing assets across different protocols
///      Key responsibilities:
///      - Handles deposits and withdrawals through protocol-specific implementations
///      - Manages gauge allocations across different targets
///      - Tracks and reports pending rewards
///      - Provides emergency shutdown functionality
abstract contract Strategy is IStrategy {
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The protocol identifier
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The accountant contract address
    /// @dev Responsible for tracking rewards and fees
    address public immutable ACCOUNTANT;

    /// @notice The locker contract address
    address public immutable LOCKER;

    /// @notice The gateway contract address
    address public immutable GATEWAY;

    /// @notice The protocol controller contract
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the vault for the gauge
    error OnlyVault();

    /// @notice Error thrown when the caller is not allowed to perform the action
    error OnlyAllowed();

    /// @notice Error thrown when trying to interact with a shutdown pool
    error PoolShutdown();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Ensures the caller is the vault registered for the gauge
    /// @param gauge The gauge to check vault authorization for
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    modifier onlyVault(address gauge) {
        require(PROTOCOL_CONTROLLER.vaults(gauge) == msg.sender, OnlyVault());
        _;
    }

    /// @notice Ensures the caller is allowed to perform the action or the gauge is shutdown
    /// @param gauge The gauge to check permissions for
    /// @custom:throws OnlyAllowed If the caller is not allowed and the gauge is not shutdown
    modifier onlyAllowed(address gauge) {
        require(
            PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig) || PROTOCOL_CONTROLLER.isShutdown(gauge),
            OnlyAllowed()
        );
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the strategy with registry, protocol ID, and accountant
    /// @param _registry The address of the protocol controller
    /// @param _protocolId The identifier for the protocol this strategy interacts with
    /// @param _accountant The address of the accountant contract
    /// @param _locker The address of the locker contract
    /// @param _gateway The address of the gateway contract
    constructor(address _registry, bytes4 _protocolId, address _accountant, address _locker, address _gateway) {
        GATEWAY = _gateway;
        ACCOUNTANT = _accountant;
        PROTOCOL_ID = _protocolId;
        PROTOCOL_CONTROLLER = IProtocolController(_registry);

        /// In some cases (L2s), the locker is the same as the gateway.
        if (_locker == address(0)) {
            LOCKER = GATEWAY;
        } else {
            LOCKER = _locker;
        }
    }

    //////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Deposits assets according to the provided allocation
    /// @dev Iterates through allocation targets and deposits to each one
    /// @param allocation The allocation data specifying where and how much to deposit
    /// @return pendingRewards Any pending rewards generated during the deposit
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws PoolShutdown If the pool is shutdown
    function deposit(IAllocator.Allocation memory allocation)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        /// If the pool is shutdown, prefer to call shutdown instead.
        /// TODO: Should we call shutdown instead, directly?
        require(!PROTOCOL_CONTROLLER.isShutdown(allocation.gauge), PoolShutdown());

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                _deposit(allocation.gauge, allocation.targets[i], allocation.amounts[i]);
            }
        }

        pendingRewards = _sync(allocation.gauge);
    }

    /// @notice Withdraws assets according to the provided allocation
    /// @dev Iterates through allocation targets and withdraws from each one
    /// @param allocation The allocation data specifying where and how much to withdraw
    /// @return pendingRewards Any pending rewards generated during the withdrawal
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws PoolShutdown If the pool is shutdown
    function withdraw(IAllocator.Allocation memory allocation)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        /// If the pool is shutdown, prefer to call shutdown instead.
        require(!PROTOCOL_CONTROLLER.isShutdown(allocation.gauge), PoolShutdown());

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                _withdraw(allocation.gauge, allocation.targets[i], allocation.amounts[i], msg.sender);
            }
        }

        pendingRewards = _sync(allocation.gauge);
    }

    /// @notice Shuts down the strategy by withdrawing all the assets and sending them to the vault
    /// @param gauge The gauge to shut down
    /// @dev Only allowed to be called by permissioned addresses, or anyone if the gauge/system is shutdown
    /// @custom:throws OnlyAllowed If the caller is not allowed and the gauge is not shutdown
    function shutdown(address gauge) external onlyAllowed(gauge) {
        /// 1. Get the vault managing the gauge.
        address vault = PROTOCOL_CONTROLLER.vaults(gauge);

        /// 2. Get the current active allocator for the protocol.
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        /// 3. Get the allocation data for the gauge.
        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        /// 4. Withdraw all the assets and send them to the vault.
        uint256 balance;
        address target;
        for (uint256 i = 0; i < targets.length; i++) {
            target = targets[i];

            if (target == LOCKER) {
                balance = IERC20(gauge).balanceOf(LOCKER);
            } else {
                balance = ISidecar(target).balanceOf();
            }

            _withdraw(gauge, target, balance, vault);
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Synchronizes the strategy state and collects pending rewards
    /// @dev Must be implemented by derived strategies to handle protocol-specific reward collection
    /// @param gauge The gauge to synchronize
    /// @return Pending rewards collected during synchronization
    function _sync(address gauge) internal virtual returns (PendingRewards memory);

    /// @notice Rebalances the strategy
    /// @dev Must be implemented by derived strategies to handle protocol-specific rebalancing
    /// @param gauge The gauge to rebalance
    function _rebalance(address gauge) internal virtual;

    /// @notice Deposits assets into a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific deposits
    /// @param gauge The gauge being deposited
    /// @param target The target to deposit into
    /// @param amount The amount to deposit
    function _deposit(address gauge, address target, uint256 amount) internal virtual;

    /// @notice Withdraws assets from a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific withdrawals
    /// @param gauge The gauge being withdrawn
    /// @param target The target to withdraw from
    /// @param amount The amount to withdraw
    /// @param receiver The address to receive the withdrawn assets
    function _withdraw(address gauge, address target, uint256 amount, address receiver) internal virtual;
}