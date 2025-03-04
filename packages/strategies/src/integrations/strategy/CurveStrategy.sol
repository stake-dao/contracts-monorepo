// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Strategy, IAllocator, ISidecar} from "src/Strategy.sol";

import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";

/// @title CurveStrategy - Curve Protocol Integration Strategy
/// @notice A strategy implementation for interacting with Curve protocol gauges
/// @dev Extends the base Strategy contract with Curve-specific functionality
///      Key responsibilities:
///      - Syncs and tracks pending rewards from Curve gauges and Sidecar contracts
///      - Handles deposits and withdrawals through Curve liquidity gauges and Sidecar contracts
///      - Executes transactions through a gateway/module manager pattern
contract CurveStrategy is Strategy {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The address of the Curve Minter contract
    /// @dev Used to account for CRV tokens from gauge rewards
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    /// @notice The bytes4 ID of the Curve protocol
    /// @dev Used to identify the Curve protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the CurveStrategy contract
    /// @param _registry The address of the protocol controller registry
    /// @param _accountant The address of the accountant contract
    /// @param _locker The address of the locker contract
    /// @param _gateway The address of the gateway contract
    constructor(address _registry, address _accountant, address _locker, address _gateway)
        Strategy(_registry, CURVE_PROTOCOL_ID, _accountant, _locker, _gateway)
    {}

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Syncs and calculates pending rewards from a Curve gauge
    /// @dev Retrieves allocation targets and calculates pending rewards for each target
    /// @param gauge The address of the Curve gauge to sync
    /// @return pendingRewards A struct containing the total and fee subject pending rewards
    function _sync(address gauge) internal view override returns (PendingRewards memory pendingRewards) {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        /// 3. Get the allocation data for the gauge.
        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        uint256 pendingRewardsAmount;
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                // Calculate pending rewards for the locker by comparing  total earned by gauge with already minted tokens
                pendingRewardsAmount =
                    ILiquidityGauge(gauge).integrate_fraction(LOCKER) - IMinter(MINTER).minted(gauge, LOCKER);

                pendingRewards.feeSubjectAmount += pendingRewardsAmount;
            } else {
                // For sidecar contracts, use their earned() function
                pendingRewardsAmount = ISidecar(target).earned();
            }

            pendingRewards.totalAmount += pendingRewardsAmount;
        }
    }

    /// @notice Deposits tokens into a Curve gauge
    /// @dev Executes a deposit transaction through the gateway/module manager
    /// @param gauge The address of the Curve gauge to deposit into
    /// @param amount The amount of tokens to deposit
    function _deposit(address gauge, uint256 amount) internal override {
        bytes memory data = abi.encodeWithSignature("deposit(uint256)", amount);

        if (LOCKER == GATEWAY) {
            // If locker is the gateway, execute directly on the gauge
            IModuleManager(GATEWAY).execTransactionFromModule(gauge, 0, data, IModuleManager.Operation.Call);
        } else {
            // Otherwise execute through the locker's execute function
            IModuleManager(GATEWAY).execTransactionFromModule(
                LOCKER,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", gauge, 0, data),
                IModuleManager.Operation.Call
            );
        }
    }

    /// @notice Withdraws tokens from a Curve gauge
    /// @dev Executes a withdraw transaction through the gateway/module manager
    /// @param gauge The address of the Curve gauge to withdraw from
    /// @param amount The amount of tokens to withdraw
    /// @param receiver The address that will receive the withdrawn tokens
    function _withdraw(address gauge, uint256 amount, address receiver) internal override {
        bytes memory data = abi.encodeWithSignature("withdraw(uint256,address)", amount, receiver);

        if (LOCKER == GATEWAY) {
            // If locker is the gateway, execute directly on the gauge
            IModuleManager(GATEWAY).execTransactionFromModule(gauge, 0, data, IModuleManager.Operation.Call);
        } else {
            // Otherwise execute through the locker's execute function
            IModuleManager(GATEWAY).execTransactionFromModule(
                LOCKER,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", gauge, 0, data),
                IModuleManager.Operation.Call
            );
        }
    }

    /// @notice Rebalances assets in a Curve gauge
    /// @param gauge The address of the Curve gauge to rebalance
    function _rebalance(address gauge) internal override {}
}
