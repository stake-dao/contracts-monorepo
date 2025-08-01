// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "src/Strategy.sol";

/// @title CurveStrategy.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org

/// @notice CurveStrategy is a specialized implementation for interacting with Curve protocol gauges.
///         It extends the base Strategy contract with Curve-specific functionality to sync and track
///         pending rewards from Curve gauges and Sidecar contracts, handle deposits and withdrawals
///         through Curve liquidity gauges, and execute transactions via the gateway pattern.
contract CurveStrategy is Strategy {
    using SafeCast for uint256;

    //////////////////////////////////////////////////////
    // --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The address of the Curve Minter contract
    /// @dev Used to account for CRV tokens from gauge rewards
    address public immutable MINTER;

    /// @notice The bytes4 ID of the Curve protocol
    /// @dev Used to identify the Curve protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Error thrown when the mint fails.
    error MintFailed();

    /// @notice Error thrown when the checkpoint fails.
    error CheckpointFailed();

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the CurveStrategy contract
    /// @param _registry The address of the protocol controller registry
    /// @param _locker The address of the locker contract
    /// @param _gateway The address of the gateway contract
    constructor(address _registry, address _locker, address _gateway, address _minter)
        Strategy(_registry, CURVE_PROTOCOL_ID, _locker, _gateway)
    {
        MINTER = _minter;
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Syncs and calculates pending rewards from a Curve gauge
    /// @dev Retrieves allocation targets and calculates pending rewards for each target
    /// @param gauge The address of the Curve gauge to sync
    /// @return pendingRewards A struct containing the total and fee subject pending rewards
    function _checkpointRewards(address gauge) internal override returns (PendingRewards memory pendingRewards) {
        address allocator = PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID);

        address[] memory targets = IAllocator(allocator).getAllocationTargets(gauge);

        /// @dev Checkpoint the locker
        require(
            _executeTransaction(gauge, abi.encodeWithSignature("user_checkpoint(address)", LOCKER)), CheckpointFailed()
        );

        uint256 pendingRewardsAmount;
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            if (target == LOCKER) {
                // Calculate pending rewards for the locker by comparing  total earned by gauge with already minted tokens
                pendingRewardsAmount =
                    ILiquidityGauge(gauge).integrate_fraction(LOCKER) - IMinter(MINTER).minted(LOCKER, gauge);

                pendingRewards.feeSubjectAmount += pendingRewardsAmount.toUint128();
            } else {
                // For sidecar contracts, use their getPendingRewards() function
                pendingRewardsAmount = ISidecar(target).getPendingRewards();
            }

            pendingRewards.totalAmount += pendingRewardsAmount.toUint128();
        }
    }

    /// @notice Deposits tokens into a Curve gauge
    /// @dev Executes a deposit transaction through the gateway/module manager
    /// @param gauge The address of the Curve gauge to deposit into
    /// @param amount The amount of tokens to deposit
    function _deposit(address, address gauge, uint256 amount) internal override {
        bytes memory data = abi.encodeWithSignature("deposit(uint256)", amount);
        require(_executeTransaction(gauge, data), DepositFailed());
    }

    /// @notice Withdraws tokens from a Curve gauge
    /// @dev Executes a withdraw transaction through the gateway/module manager
    /// @param gauge The address of the Curve gauge to withdraw from
    /// @param amount The amount of tokens to withdraw
    /// @param receiver The address that will receive the withdrawn tokens
    function _withdraw(address asset, address gauge, uint256 amount, address receiver) internal override {
        bytes memory data = abi.encodeWithSignature("withdraw(uint256)", amount);
        require(_executeTransaction(gauge, data), WithdrawFailed());

        // 2. Transfer the LP tokens to receiver
        data = abi.encodeWithSignature("transfer(address,uint256)", receiver, amount);
        require(_executeTransaction(asset, data), TransferFailed());
    }

    /// @notice Harvests rewards from a Curve gauge
    /// @param gauge The address of the Curve gauge to harvest from
    function _harvestLocker(address gauge, bytes memory) internal override returns (uint256 rewardAmount) {
        /// 1. Snapshot the balance before minting.
        uint256 _before = IERC20(REWARD_TOKEN).balanceOf(address(LOCKER));

        /// @dev Locker is deployed on mainnet.
        /// @dev If the locker is the gateway, we need to mint the rewards via the gateway
        /// as it means the strategy is deployed on sidechain.
        if (LOCKER != GATEWAY) {
            /// 2. Mint the rewards of the gauge to the locker.
            IMinter(MINTER).mint_for(gauge, address(LOCKER));
        } else {
            /// 2. Mint the rewards of the gauge to the locker via the gateway.
            bytes memory data = abi.encodeWithSignature("mint(address)", gauge);
            require(_executeTransaction(MINTER, data), MintFailed());
        }

        /// 3. Calculate the reward amount.
        rewardAmount = IERC20(REWARD_TOKEN).balanceOf(address(LOCKER)) - _before;
    }
}
