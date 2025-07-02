// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {ProtocolContext} from "src/ProtocolContext.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";

/// @title Strategy - Protocol-agnostic yield strategy orchestrator
/// @notice Manages deposits/withdrawals across multiple yield sources (locker + sidecars)
/// @dev Abstract base that protocol-specific strategies inherit from. Key features:
///      - Routes funds between locker and sidecars based on allocator decisions
///      - Handles reward harvesting with transient storage for gas optimization
///      - Emergency shutdown transfers all funds back to vault
///      - Rebalancing redistributes funds when allocations change
abstract contract Strategy is IStrategy, ProtocolContext {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using TransientSlot for *;

    /// @dev Transient storage slot for batching reward transfers during harvest
    /// @dev Gas optimization: reduces multiple ERC20 transfers to single batch transfer
    bytes32 internal constant FLUSH_AMOUNT_SLOT = keccak256("strategy.flushAmount");

    //////////////////////////////////////////////////////
    // --- ERRORS & EVENTS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not the vault for the gauge
    error OnlyVault();

    /// @notice Error thrown when the caller is not the accountant for the strategy
    error OnlyAccountant();

    /// @notice Error thrown when the caller is not the protocol controller
    error OnlyProtocolController();

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

    /// @notice Error thrown when deposits are attempted while protocol is paused
    error DepositsPaused();

    /// @notice Event emitted when the strategy is shutdown
    event Shutdown(address indexed gauge);

    /// @notice Event emitted when the strategy is rebalanced
    event Rebalance(address indexed gauge, address[] targets, uint256[] amounts);

    //////////////////////////////////////////////////////
    // --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Restricts functions to the vault associated with the gauge
    modifier onlyVault(address gauge) {
        require(PROTOCOL_CONTROLLER.vaults(gauge) == msg.sender, OnlyVault());
        _;
    }

    /// @notice Restricts functions to the protocol controller
    modifier onlyProtocolController() {
        require(PROTOCOL_CONTROLLER.isShutdown(msg.sender), OnlyProtocolController());
        _;
    }

    /// @notice Restricts harvest flush operations to the accountant
    modifier onlyAccountant() {
        require(ACCOUNTANT == msg.sender, OnlyAccountant());
        _;
    }

    /// @notice Allows authorized addresses OR anyone if gauge is shutdown
    /// @dev Enables permissionless emergency withdrawals during shutdowns
    modifier onlyAllowed(address gauge) {
        require(
            PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig) || PROTOCOL_CONTROLLER.isShutdown(gauge),
            OnlyAllowed()
        );
        _;
    }

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
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
    // --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Deposits LP tokens into gauge/sidecars according to allocator's distribution
    /// @dev Called by vault after transferring LP tokens to targets
    /// @param allocation Contains targets and amounts for deposit
    /// @param policy Whether to harvest rewards during deposit
    /// @return pendingRewards Rewards claimed if HARVEST policy
    /// @custom:throws GaugeShutdown Prevents deposits to shutdown gauges
    /// @custom:throws DepositsPaused Prevents deposits when protocol is paused
    function deposit(IAllocator.Allocation calldata allocation, HarvestPolicy policy)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        require(!PROTOCOL_CONTROLLER.isShutdown(allocation.gauge), GaugeShutdown());
        require(!PROTOCOL_CONTROLLER.isPaused(PROTOCOL_ID), DepositsPaused());

        // Execute deposits on each target (locker or sidecar)
        for (uint256 i; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                if (allocation.targets[i] == LOCKER) {
                    _deposit(allocation.asset, allocation.gauge, allocation.amounts[i]);
                } else {
                    ISidecar(allocation.targets[i]).deposit(allocation.amounts[i]);
                }
            }
        }

        pendingRewards = _harvestOrCheckpoint(allocation.gauge, policy);
    }

    /// @notice Withdraws LP tokens from gauge/sidecars and sends to receiver
    /// @dev Skips withdrawal if gauge is shutdown (requires shutdown() instead)
    /// @param allocation Contains targets and amounts for withdrawal
    /// @param policy Whether to harvest rewards during withdrawal
    /// @param receiver Address to receive the LP tokens
    /// @return pendingRewards Rewards claimed if HARVEST policy
    function withdraw(IAllocator.Allocation calldata allocation, IStrategy.HarvestPolicy policy, address receiver)
        external
        override
        onlyVault(allocation.gauge)
        returns (PendingRewards memory pendingRewards)
    {
        address gauge = allocation.gauge;

        // For shutdown gauges, only sync rewards without withdrawing
        // @dev Prevents loss of user funds by ensuring no withdrawals after shutdown
        if (PROTOCOL_CONTROLLER.isShutdown(gauge)) return _harvestOrCheckpoint(gauge, policy);

        // Execute withdrawals from each target
        for (uint256 i; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] > 0) {
                if (allocation.targets[i] == LOCKER) {
                    _withdraw(allocation.asset, gauge, allocation.amounts[i], receiver);
                } else {
                    ISidecar(allocation.targets[i]).withdraw(allocation.amounts[i], receiver);
                }
            }
        }

        return _harvestOrCheckpoint(gauge, policy);
    }

    /// @notice Claims rewards from gauge and sidecars (accountant batch harvest)
    /// @dev Uses transient storage to defer reward transfers for gas efficiency
    /// @param gauge The gauge to harvest rewards from
    /// @param extraData Protocol-specific data for claiming
    /// @return pendingRewards Total rewards claimed from all sources
    function harvest(address gauge, bytes memory extraData)
        external
        override
        onlyAccountant
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        return _harvest(gauge, extraData, true);
    }

    /// @notice Transfers accumulated rewards to accountant after batch harvest
    /// @dev Called once after harvesting multiple gauges to save gas
    function flush() public onlyAccountant {
        uint256 flushAmount = _getFlushAmount();
        if (flushAmount == 0) return;

        _transferToAccountant(flushAmount);
        _setFlushAmount(0);
    }

    /// @notice Emergency withdrawal of all funds back to vault
    /// @dev Anyone can call if gauge is shutdown, ensuring user fund recovery
    /// @param gauge The gauge to withdraw all funds from
    /// @custom:throws AlreadyShutdown If already fully withdrawn
    function shutdown(address gauge) public onlyProtocolController {
        address vault = PROTOCOL_CONTROLLER.vaults(gauge);
        address asset = IERC4626(vault).asset();
        address[] memory targets = _getAllocationTargets(gauge);

        // Withdraw everything from locker and sidecars to vault
        _withdrawFromAllTargets(asset, gauge, targets, vault);

        emit Shutdown(gauge);
    }

    /// @notice Redistributes funds between targets when allocations change
    /// @dev Withdraws all funds to strategy then re-deposits per new allocation
    /// @param gauge The gauge to rebalance
    /// @custom:throws RebalanceNotNeeded If only one target (nothing to rebalance)
    /// @custom:throws DepositsPaused Prevents rebalancing when protocol is paused
    function rebalance(address gauge) external {
        require(!PROTOCOL_CONTROLLER.isShutdown(gauge), GaugeShutdown());
        require(!PROTOCOL_CONTROLLER.isPaused(PROTOCOL_ID), DepositsPaused());

        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);
        IERC20 asset = IERC20(PROTOCOL_CONTROLLER.asset(gauge));
        uint256 currentBalance = balanceOf(gauge);
        address[] memory targets = _getAllocationTargets(gauge);

        // Withdraw everything to this contract
        _withdrawFromAllTargets(address(asset), gauge, targets, address(this));

        // Get new allocation from allocator
        IAllocator.Allocation memory allocation =
            IAllocator(allocator).getRebalancedAllocation(address(asset), gauge, currentBalance);

        uint256 allocationLength = allocation.targets.length;
        require(allocationLength > 1, RebalanceNotNeeded());

        // Re-deposit according to new allocation
        for (uint256 i; i < allocationLength; i++) {
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

        emit Rebalance(gauge, allocation.targets, allocation.amounts);
    }

    /// @notice Total LP tokens managed across all targets for a gauge
    /// @dev Sums balances from locker and all sidecars
    /// @param gauge The gauge to check balance for
    /// @return balance Combined LP token balance
    function balanceOf(address gauge) public view virtual returns (uint256 balance) {
        address[] memory targets = _getAllocationTargets(gauge);

        uint256 length = targets.length;
        for (uint256 i; i < length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                balance += IBalanceProvider(gauge).balanceOf(target);
            } else {
                balance += ISidecar(target).balanceOf();
            }
        }
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Gets allocation targets for a gauge
    /// @param gauge The gauge to get targets for
    /// @return targets Array of target addresses
    function _getAllocationTargets(address gauge) internal view returns (address[] memory targets) {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);
        targets = IAllocator(allocator).getAllocationTargets(gauge);
    }

    /// @notice Withdraws assets from all targets
    /// @param asset The asset to withdraw
    /// @param gauge The gauge to withdraw from
    /// @param targets Array of target addresses
    /// @param receiver Address to receive the withdrawn assets
    function _withdrawFromAllTargets(address asset, address gauge, address[] memory targets, address receiver)
        internal
    {
        uint256 length = targets.length;
        for (uint256 i; i < length; i++) {
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

    /// @notice Claims rewards from locker and all sidecars
    /// @dev Locker rewards are fee-subject, sidecar rewards may not be
    /// @param gauge The gauge to harvest from
    /// @param extraData Protocol-specific harvest parameters
    /// @param deferRewards If true, accumulate in transient storage for batch transfer (gas optimization)
    /// @return pendingRewards Total and fee-subject reward amounts
    function _harvest(address gauge, bytes memory extraData, bool deferRewards)
        internal
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        address[] memory targets = _getAllocationTargets(gauge);

        uint256 pendingRewardsAmount;
        uint256 length = targets.length;
        for (uint256 i; i < length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                pendingRewardsAmount = _harvestLocker(gauge, extraData);
                pendingRewards.feeSubjectAmount = pendingRewardsAmount.toUint128();

                if (deferRewards) {
                    // Batch transfers: accumulate in transient storage
                    uint256 currentFlushAmount = _getFlushAmount();
                    _setFlushAmount(currentFlushAmount + pendingRewardsAmount);
                } else {
                    // Direct transfer for HARVEST policy
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
    /// @param policy The harvest policy to use
    /// @return pendingRewards The pending rewards after harvesting or synchronization
    function _harvestOrCheckpoint(address gauge, IStrategy.HarvestPolicy policy)
        internal
        returns (PendingRewards memory pendingRewards)
    {
        pendingRewards =
            policy == IStrategy.HarvestPolicy.HARVEST ? _harvest(gauge, "", false) : _checkpointRewards(gauge);
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL VIRTUAL FUNCTIONS
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
    function _checkpointRewards(address gauge) internal virtual returns (PendingRewards memory);

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
    function _withdraw(address asset, address gauge, uint256 amount, address receiver) internal virtual;
}
