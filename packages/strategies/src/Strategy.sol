// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {IProtocolController, ProtocolContext} from "src/ProtocolContext.sol";

/// @title Strategy - Abstract Base Strategy Contract
/// @notice A base contract for implementing protocol-specific strategies
/// @dev Provides core functionality for depositing, withdrawing, and managing assets across different protocols
///      Key responsibilities:
///      - Handles deposits and withdrawals through protocol-specific implementations
///      - Manages gauge allocations across different targets
///      - Tracks and reports pending rewards
///      - Provides emergency shutdown functionality
abstract contract Strategy is IStrategy, ProtocolContext {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the vault for the gauge
    error OnlyVault();

    /// @notice Error thrown when the caller is not the accountant for the strategy
    error OnlyAccountant();

    /// @notice Error thrown when the caller is not allowed to perform the action
    error OnlyAllowed();

    /// @notice Error thrown when trying to interact with a shutdown gauge
    error GaugeShutdown();

    /// @notice Error thrown when rebalance is not needed
    error RebalanceNotNeeded();

    /// @notice Error thrown when rebalance goes wrong or is not implemented
    error RebalanceGoneWrongOrNotImplemented();

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

    /// @notice Ensures the caller is the accountant for the strategy
    /// @custom:throws OnlyAccountant If the caller is not the accountant for the strategy
    modifier onlyAccountant() {
        require(ACCOUNTANT == msg.sender, OnlyAccountant());
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

    /// @notice Initializes the strategy with registry, protocol ID, and locker and gateway
    /// @param _registry The address of the protocol controller
    /// @param _protocolId The identifier for the protocol this strategy interacts with
    /// @param _locker The address of the locker contract
    /// @param _gateway The address of the gateway contract
    constructor(address _registry, bytes4 _protocolId, address _locker, address _gateway)
        ProtocolContext(_protocolId, _registry, _locker, _gateway)
    {}

    //////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Deposits assets according to the provided allocation
    /// @dev Iterates through allocation targets and deposits to each one
    /// @param allocation The allocation data specifying where and how much to deposit
    /// @return pendingRewards Any pending rewards generated during the deposit
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws GaugeShutdown If the pool is shutdown
    function deposit(IAllocator.Allocation memory allocation)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        /// If the pool is shutdown, prefer to call shutdown instead.
        /// TODO: Should we call shutdown instead, directly?
        require(!PROTOCOL_CONTROLLER.isShutdown(allocation.gauge), GaugeShutdown());

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                if (allocation.targets[i] == LOCKER) {
                    _deposit(allocation.gauge, allocation.amounts[i]);
                } else {
                    ISidecar(allocation.targets[i]).deposit(allocation.amounts[i]);
                }
            }
        }

        pendingRewards = _sync(allocation.gauge);
    }

    /// @notice Withdraws assets according to the provided allocation
    /// @dev Iterates through allocation targets and withdraws from each one
    /// @param allocation The allocation data specifying where and how much to withdraw
    /// @return pendingRewards Any pending rewards generated during the withdrawal
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws GaugeShutdown If the pool is shutdown
    function withdraw(IAllocator.Allocation memory allocation)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        /// If the pool is shutdown, prefer to call shutdown instead.
        require(!PROTOCOL_CONTROLLER.isShutdown(allocation.gauge), GaugeShutdown());

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                if (allocation.targets[i] == LOCKER) {
                    _withdraw(allocation.gauge, allocation.amounts[i], msg.sender);
                } else {
                    ISidecar(allocation.targets[i]).withdraw(allocation.amounts[i], msg.sender);
                }
            }
        }

        pendingRewards = _sync(allocation.gauge);
    }

    /// @notice Harvests rewards from a gauge
    /// @param gauge The gauge address to harvest from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards after harvesting
    /// @dev Called using delegatecall from the Accountant contract
    /// @dev Essentialy the same implementation as Strategy.sync() but this function claims rewards and returns them
    function harvest(address gauge, bytes calldata extraData)
        external
        override
        onlyAccountant
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        uint256 pendingRewardsAmount;
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                pendingRewardsAmount = _harvest(gauge, extraData);
                pendingRewards.feeSubjectAmount = pendingRewardsAmount.toUint128();
            } else {
                pendingRewardsAmount = ISidecar(target).claim();
            }

            pendingRewards.totalAmount += pendingRewardsAmount.toUint128();
        }

        return pendingRewards;
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
                balance = IBalanceProvider(gauge).balanceOf(LOCKER);

                _withdraw(gauge, balance, vault);
            } else {
                balance = ISidecar(target).balanceOf();

                ISidecar(target).withdraw(balance, vault);
            }
        }
    }

    /// @notice Rebalances the strategy
    /// @param gauge The gauge to rebalance
    function rebalance(address gauge) external {
        /// 1. Get the allocator.
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        /// 2. Get the asset.
        IERC20 asset = IERC20(PROTOCOL_CONTROLLER.asset(gauge));

        /// 3. Snapshot the current balance.
        uint256 currentBalance = balanceOf(gauge);

        /// 4. Get the allocation amounts for the gauge.
        IAllocator.Allocation memory allocation = IAllocator(allocator).getDepositAllocation(gauge, currentBalance);

        /// 5. Ensure the allocation has more than one target.
        require(allocation.targets.length > 1, RebalanceNotNeeded());

        /// 6. Withdraw the amounts from the gauge.
        address target;
        uint256 balance;
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            target = allocation.targets[i];

            if (target == LOCKER) {
                balance = IBalanceProvider(gauge).balanceOf(LOCKER);
                _withdraw(gauge, balance, address(this));
            } else {
                balance = ISidecar(target).balanceOf();
                ISidecar(target).withdraw(balance, address(this));
            }
        }

        /// 7. Deposit the amounts into the gauge with new allocations
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            target = allocation.targets[i];
            asset.safeTransfer(target, allocation.amounts[i]);

            if (target == LOCKER) {
                _deposit(gauge, allocation.amounts[i]);
            } else {
                ISidecar(target).deposit(allocation.amounts[i]);
            }
        }

        /// 8. Return true if the balance is the same as the current balance, meaning the rebalance was successful.
        require(currentBalance == balanceOf(gauge), RebalanceGoneWrongOrNotImplemented());
    }

    /// @notice Returns the balance of the strategy
    /// @param gauge The gauge to get the balance of
    /// @return balance The balance of the strategy
    function balanceOf(address gauge) public view virtual returns (uint256 balance) {
        balance = IBalanceProvider(gauge).balanceOf(LOCKER);

        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);
        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        for (uint256 i = 0; i < targets.length; i++) {
            balance += ISidecar(targets[i]).balanceOf();
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Synchronizes state of pending rewards.
    /// @dev Must be implemented by derived strategies to handle protocol-specific reward collection
    /// @param gauge The gauge to synchronize
    /// @return Pending rewards collected during synchronization
    function _sync(address gauge) internal virtual returns (PendingRewards memory);

    /// @notice Harvests rewards from a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific reward collection
    /// @param gauge The gauge to harvest rewards from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards collected during harvesting
    function _harvest(address gauge, bytes calldata extraData) internal virtual returns (uint256 pendingRewards);

    /// @notice Deposits assets into a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific deposits
    /// @param gauge The gauge to deposit into
    /// @param amount The amount to deposit
    function _deposit(address gauge, uint256 amount) internal virtual;

    /// @notice Withdraws assets from a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific withdrawals
    /// @param gauge The gauge to withdraw from
    /// @param amount The amount to withdraw
    /// @param receiver The address to receive the withdrawn assets
    function _withdraw(address gauge, uint256 amount, address receiver) internal virtual {}
}
