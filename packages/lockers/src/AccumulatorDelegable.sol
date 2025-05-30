// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {IVeBoost} from "src/interfaces/IVeBoost.sol";

/// @title AccumulatorDelegable
/// @notice This contract is an extension of the AccumulatorBase, designed to manage and distribute rewards
///         to a delegation contract in a decentralized finance (DeFi) protocol. It leverages the veBoost
///         mechanism to enhance reward distribution without transferring governance rights.
///
///         The contract holds reward tokens and distributes them to a specified delegation contract based on
///         the boost received and the balance of veTokens (e.g., veCRV). It applies a multiplier to the
///         calculated delegation share, allowing for flexible reward strategies.
abstract contract AccumulatorDelegable is AccumulatorBase {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    address public immutable token;
    address public immutable veToken;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////
    address public veBoost;
    address public veBoostDelegation;
    uint256 public multiplier;

    ///////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when the multiplier is set
    event MultiplierSet(uint256 oldMultiplier, uint256 newMultiplier);

    /// @notice Emitted when the veBoost is set
    event VeBoostSet(address oldVeBoost, address newVeBoost);

    /// @notice Emitted when the veBoostDelegation is set
    event VeBoostDelegationSet(address oldVeBoostDelegation, address newVeBoostDelegation);

    /// @notice Emitted when the rewards are shared with the delegation contract
    event RewardsSharedWithDelegation(address token, address to, uint256 amount);

    /// @notice Constructor for the AccumulatorDelegable contract.
    /// @param _gauge The address of the gauge.
    /// @param _rewardToken The address of the reward token.
    /// @param _locker The address of the locker.
    /// @param _governance The address of the governance.
    /// @param _token The address of the reward token managed by the contract.
    /// @param _veToken The address of the veToken (e.g., veCRV) used to calculate the boost.
    /// @param _veBoost The address of the veBoost contract, which manages the boost received.
    /// @param _veBoostDelegation The address of the delegation contract to which rewards are distributed.
    /// @param _multiplier A scaling factor applied to the calculated delegation share.
    constructor(
        address _gauge,
        address _rewardToken,
        address _locker,
        address _governance,
        address _token,
        address _veToken,
        address _veBoost,
        address _veBoostDelegation,
        uint256 _multiplier
    ) AccumulatorBase(_gauge, _rewardToken, _locker, _governance) {
        token = _token;
        veToken = _veToken;
        veBoost = _veBoost;
        veBoostDelegation = _veBoostDelegation;
        multiplier = _multiplier;
    }

    /// @notice Shares the rewards with the delegation contract
    function _shareWithDelegation() internal returns (uint256 delegationShare) {
        uint256 amount = ERC20(token).balanceOf(address(this));
        if (amount == 0) return 0;
        if (veBoost == address(0) || veBoostDelegation == address(0)) return 0;

        /// Share the rewards with the delegation contract.
        uint256 boostReceived = IVeBoost(veBoost).received_balance(locker);
        if (boostReceived == 0) return 0;

        /// Get the veToken balance of the locker.
        uint256 lockerVEToken = ERC20(veToken).balanceOf(locker);

        /// Calculate the percentage of token delegated to the VeBoost contract.
        uint256 bpsDelegated = boostReceived * DENOMINATOR / lockerVEToken;

        /// Calculate the expected delegation share.
        delegationShare = amount * bpsDelegated / DENOMINATOR;

        /// Apply the multiplier.
        if (multiplier != 0) delegationShare = delegationShare * multiplier / DENOMINATOR;

        SafeTransferLib.safeTransfer(token, veBoostDelegation, delegationShare);
        emit RewardsSharedWithDelegation(token, veBoostDelegation, delegationShare);
    }

    ///////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Sets the multiplier
    /// @param _multiplier The new multiplier
    function setMultiplier(uint256 _multiplier) external onlyGovernance {
        emit MultiplierSet(multiplier, _multiplier);
        multiplier = _multiplier;
    }

    /// @notice Sets the veBoost
    /// @param _veBoost The new veBoost
    function setVeBoost(address _veBoost) external onlyGovernance {
        emit VeBoostSet(veBoost, _veBoost);
        veBoost = _veBoost;
    }

    /// @notice Sets the veBoostDelegation
    /// @param _veBoostDelegation The new veBoostDelegation
    function setVeBoostDelegation(address _veBoostDelegation) external onlyGovernance {
        emit VeBoostDelegationSet(veBoostDelegation, _veBoostDelegation);
        veBoostDelegation = _veBoostDelegation;
    }
}
