// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";

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
    using TransientSlot for *;

    /// @dev Slot for the flush amount in transient storage
    bytes32 internal constant FLUSH_AMOUNT_SLOT = keccak256("strategy.flushAmount");

    //////////////////////////////////////////////////////
    /// --- ERRORS & EVENTS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the vault for the gauge
    error OnlyVault();

    /// @notice Error thrown when the caller is not the accountant for the strategy
    error OnlyAccountant();

    /// @notice Error thrown when the caller is not allowed to perform the action
    error OnlyAllowed();

    /// @notice Error thrown when trying to interact with a shutdown gauge
    error GaugeShutdown();

    /// @notice Error thrown when the deposit fails
    error DepositFailed();

    /// @notice Error thrown when the withdraw fails
    error WithdrawFailed();

    /// @notice Error thrown when the transfer fails
    error TransferFailed();

    /// @notice Error thrown when the approve fails
    error ApproveFailed();

    /// @notice Error thrown when rebalance is not needed
    error RebalanceNotNeeded();

    /// @notice Error thrown when the strategy is already shutdown
    error AlreadyShutdown();

    /// @notice Error thrown when the transfer to the accountant fails
    error TransferToAccountantFailed();

    /// @notice Event emitted when the strategy is shutdown
    event Shutdown(address indexed gauge);

    /// @notice Event emitted when the strategy is rebalanced
    event Rebalance(address indexed gauge, address[] targets, uint256[] amounts);

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
    /// @param doHarvest Whether to harvest rewards during the deposit
    /// @return pendingRewards Any pending rewards generated during the deposit
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws GaugeShutdown If the pool is shutdown
    function deposit(IAllocator.Allocation memory allocation, bool doHarvest)
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
                    _deposit(allocation.asset, allocation.gauge, allocation.amounts[i]);
                } else {
                    ISidecar(allocation.targets[i]).deposit(allocation.amounts[i]);
                }
            }
        }

        pendingRewards = _harvestOrSync(allocation.gauge, doHarvest);
    }

    /// @notice Withdraws assets according to the provided allocation
    /// @dev Iterates through allocation targets and withdraws from each one
    /// @param allocation The allocation data specifying where and how much to withdraw
    /// @param doHarvest Whether to harvest rewards during the withdrawal
    /// @return pendingRewards Any pending rewards generated during the withdrawal
    /// @custom:throws OnlyVault If the caller is not the registered vault for the gauge
    /// @custom:throws GaugeShutdown If the pool is shutdown
    function withdraw(IAllocator.Allocation memory allocation, bool doHarvest, address receiver)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        address gauge = allocation.gauge;

        /// If the pool is shutdown, return the pending rewards.
        /// Use the shutdown function to withdraw the funds.
        if (PROTOCOL_CONTROLLER.isShutdown(gauge)) return _harvestOrSync(gauge, doHarvest);

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            /// When the receiver is not set, it means it's a transfer of the vault shares and we need to checkpoint by
            /// withdrawing 0.
            if (allocation.amounts[i] > 0 || receiver == address(0)) {
                if (allocation.targets[i] == LOCKER) {
                    _withdraw(allocation.asset, gauge, allocation.amounts[i], receiver);
                } else {
                    ISidecar(allocation.targets[i]).withdraw(allocation.amounts[i], receiver);
                }
            }
        }

        return _harvestOrSync(gauge, doHarvest);
    }

    /// @notice Harvests rewards from a gauge
    /// @param gauge The gauge address to harvest from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards after harvesting
    /// @dev Called using delegatecall from the Accountant contract
    function harvest(address gauge, bytes memory extraData)
        external
        override
        onlyAccountant
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        return _harvest(gauge, extraData, true);
    }

    /// @notice Flushes the reward token to the locker
    /// @dev Only allowed to be called by the accountant during harvest operation
    function flush() public onlyAccountant {
        // Get flush amount from transient storage.
        uint256 flushAmount = _getFlushAmount();
        if (flushAmount == 0) return;

        // Transfer the flush amount to the accountant.
        _transferToAccountant(flushAmount);

        // Reset the flush amount in transient storage.
        _setFlushAmount(0);
    }

    /// @notice Shuts down the strategy by withdrawing all the assets and sending them to the vault
    /// @param gauge The gauge to shut down
    /// @dev Only allowed to be called by permissioned addresses, or anyone if the gauge/system is shutdown
    /// @custom:throws OnlyAllowed If the caller is not allowed and the gauge is not shutdown
    function shutdown(address gauge) public onlyAllowed(gauge) {
        require(!PROTOCOL_CONTROLLER.isFullyWithdrawn(gauge), AlreadyShutdown());

        /// 1. Get the vault managing the gauge.
        address vault = PROTOCOL_CONTROLLER.vaults(gauge);

        /// 2. Get the asset.
        address asset = IERC4626(vault).asset();

        /// 3. Get the allocation targets for the gauge.
        address[] memory targets = _getAllocationTargets(gauge);

        /// 4. Withdraw all the assets and send them to the vault.
        _withdrawFromAllTargets(asset, gauge, targets, vault);

        /// 5. Mark the gauge as fully withdrawn.
        PROTOCOL_CONTROLLER.markGaugeAsFullyWithdrawn(gauge);

        /// 6. Emit the shutdown event.
        emit Shutdown(gauge);
    }

    /// @notice Rebalances the strategy
    /// @param gauge The gauge to rebalance
    function rebalance(address gauge) external {
        /// If the gauge is shutdown, return.
        require(!PROTOCOL_CONTROLLER.isShutdown(gauge), GaugeShutdown());

        /// 1. Get the allocator.
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        /// 2. Get the asset.
        IERC20 asset = IERC20(PROTOCOL_CONTROLLER.asset(gauge));

        /// 3. Snapshot the current balance.
        uint256 currentBalance = balanceOf(gauge);

        /// 4. Get the allocation targets for the gauge.
        address[] memory targets = _getAllocationTargets(gauge);

        /// 5. Withdraw all assets from all targets to this contract
        _withdrawFromAllTargets(address(asset), gauge, targets, address(this));

        /// 6. Get the allocation amounts for the gauge.
        IAllocator.Allocation memory allocation =
            IAllocator(allocator).getRebalancedAllocation(address(asset), gauge, currentBalance);

        /// 7. Ensure the allocation has more than one target.
        require(allocation.targets.length > 1, RebalanceNotNeeded());

        /// 8. Deposit the amounts into the gauge with new allocations
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            address target = allocation.targets[i];
            uint256 amount = allocation.amounts[i];

            asset.safeTransfer(target, amount);

            if (amount > 0) {
                if (target == LOCKER) {
                    _deposit(address(asset), gauge, amount);
                } else {
                    ISidecar(target).deposit(amount);
                }
            }
        }

        /// 8. Emit the rebalance event.
        emit Rebalance(gauge, allocation.targets, allocation.amounts);
    }

    /// @notice Returns the balance of the strategy
    /// @param gauge The gauge to get the balance of
    /// @return balance The balance of the strategy
    function balanceOf(address gauge) public view virtual returns (uint256 balance) {
        address[] memory targets = _getAllocationTargets(gauge);

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                balance += IBalanceProvider(gauge).balanceOf(target);
            } else {
                balance += ISidecar(target).balanceOf();
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Gets allocation targets for a gauge
    /// @param gauge The gauge to get targets for
    /// @return targets Array of target addresses
    function _getAllocationTargets(address gauge) internal view returns (address[] memory) {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);
        return IAllocator(allocator).getAllocationTargets(gauge);
    }

    /// @notice Withdraws assets from all targets
    /// @param asset The asset to withdraw
    /// @param gauge The gauge to withdraw from
    /// @param targets Array of target addresses
    /// @param receiver Address to receive the withdrawn assets
    function _withdrawFromAllTargets(address asset, address gauge, address[] memory targets, address receiver)
        internal
    {
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            uint256 balance;

            if (target == LOCKER) {
                balance = IBalanceProvider(gauge).balanceOf(LOCKER);
                if (balance > 0) {
                    _withdraw(asset, gauge, balance, receiver);
                }
            } else {
                balance = ISidecar(target).balanceOf();
                if (balance > 0) {
                    ISidecar(target).withdraw(balance, receiver);
                }
            }
        }
    }

    /// @notice Handles the harvest operation
    /// @param gauge The gauge to harvest from
    /// @param extraData Additional data needed for harvesting
    /// @param deferRewards Whether to store rewards for later flush (true) or transfer immediately (false)
    /// @return pendingRewards The pending rewards after harvesting
    function _harvest(address gauge, bytes memory extraData, bool deferRewards)
        internal
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        address[] memory targets = _getAllocationTargets(gauge);

        uint256 pendingRewardsAmount;
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                pendingRewardsAmount = _harvestLocker(gauge, extraData);
                pendingRewards.feeSubjectAmount = pendingRewardsAmount.toUint128();

                if (deferRewards) {
                    // Update flush amount in transient storage
                    uint256 currentFlushAmount = _getFlushAmount();
                    _setFlushAmount(currentFlushAmount + pendingRewardsAmount);
                } else {
                    // Transfer the pending rewards to the accountant directly
                    _transferToAccountant(pendingRewardsAmount);
                }
            } else {
                pendingRewardsAmount = ISidecar(target).claim();
            }

            pendingRewards.totalAmount += pendingRewardsAmount.toUint128();
        }

        return pendingRewards;
    }

    /// @notice Harvests or synchronizes rewards
    /// @param gauge The gauge to harvest or synchronize from
    /// @param doHarvest Whether to perform a harvest operation
    /// @return pendingRewards The pending rewards after harvesting or synchronization
    function _harvestOrSync(address gauge, bool doHarvest) internal returns (PendingRewards memory pendingRewards) {
        pendingRewards = doHarvest ? _harvest(gauge, "", false) : _sync(gauge);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Gets the flush amount from transient storage
    /// @return The flush amount
    function _getFlushAmount() internal view virtual returns (uint256) {
        return FLUSH_AMOUNT_SLOT.asUint256().tload();
    }

    /// @notice Sets the flush amount in transient storage
    /// @param amount The amount to set
    function _setFlushAmount(uint256 amount) internal virtual {
        FLUSH_AMOUNT_SLOT.asUint256().tstore(amount);
    }

    /// @notice Flushes the reward token to the accountant
    /// @dev Transfers the specified amount of reward tokens to the accountant
    /// @param amount The amount of reward tokens to flush
    function _transferToAccountant(uint256 amount) internal {
        if (amount > 0) {
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, ACCOUNTANT, amount);
            require(_executeTransaction(address(REWARD_TOKEN), data), TransferToAccountantFailed());
        }
    }

    /// @notice Synchronizes state of pending rewards.
    /// @dev Must be implemented by derived strategies to handle protocol-specific reward collection
    /// @param gauge The gauge to synchronize
    /// @return Pending rewards collected during synchronization
    function _sync(address gauge) internal virtual returns (PendingRewards memory);

    /// @notice Harvests rewards from the locker
    /// @dev Must be implemented by derived strategies to handle protocol-specific reward collection
    /// @param gauge The gauge to harvest rewards from
    /// @param extraData Additional data needed for harvesting (protocol-specific)
    /// @return pendingRewards The pending rewards collected during harvesting
    function _harvestLocker(address gauge, bytes memory extraData) internal virtual returns (uint256 pendingRewards);

    /// @notice Deposits assets into a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific deposits
    /// @param asset The asset to deposit
    /// @param gauge The gauge to deposit into
    /// @param amount The amount to deposit
    function _deposit(address asset, address gauge, uint256 amount) internal virtual;

    /// @notice Withdraws assets from a specific target
    /// @dev Must be implemented by derived strategies to handle protocol-specific withdrawals
    /// @param asset The asset to withdraw
    /// @param gauge The gauge to withdraw from
    /// @param amount The amount to withdraw
    /// @param receiver The address to receive the withdrawn assets
    function _withdraw(address asset, address gauge, uint256 amount, address receiver) internal virtual {}
}
