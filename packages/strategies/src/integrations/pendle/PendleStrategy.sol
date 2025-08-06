// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strategy} from "src/Strategy.sol";
import {IPendleGauge} from "src/interfaces/IPendleGauge.sol";
import {IPendleMarket} from "src/interfaces/IPendleMarket.sol";
import {IRewardReceiver} from "src/interfaces/IRewardReceiver.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title PendleStrategy
/// @notice Stake DAO Strategy implementation for Pendle V2 markets
/// @dev In Pendle every market LP token is the gauge share token, so merely
///      holding the LP inside the Locker counts as staking. No explicit deposit
///      or withdraw calls are required; the strategy therefore focuses on:
///        1. Moving LP tokens out of the Locker on withdrawals.
///        2. Triggering `redeemRewards` to harvest *all* rewards.
///        3. Reporting harvested amounts to the Accountant.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org
contract PendleStrategy is Strategy {
    using SafeCast for uint256;

    //////////////////////////////////////////////////////
    // --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Bytes-4 protocol identifier for Pendle
    bytes4 private constant PENDLE_PROTOCOL_ID = bytes4(keccak256("PENDLE"));

    /// @notice Thrown when the reward harvest fails
    error HarvestFailed();

    /// @notice Thrown when the reward checkpoint fails
    error CheckpointFailed();

    /// @notice Thrown when the reward receiver is not set
    error RewardReceiverNotSet();

    /// @notice Thrown when the Pendle reward arrays are not the same length
    error PendleRewardArraysLengthMismatch();

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @param _registry  Address of ProtocolController
    /// @param _locker    The Locker that actually holds LP & vePENDLE
    /// @param _gateway   Safe module that executes calls on behalf of the Locker
    constructor(address _registry, address _locker, address _gateway)
        Strategy(_registry, PENDLE_PROTOCOL_ID, _locker, _gateway)
    {}

    //////////////////////////////////////////////////////
    // --- INTERNAL STRATEGY HOOKS
    //////////////////////////////////////////////////////

    /// @notice Estimate claimable PENDLE without actually harvesting (CHECKPOINT mode).
    /// @param gauge  Pendle gauge (also the market and the LP token).
    function _checkpointRewards(address gauge) internal override returns (PendingRewards memory pendingRewards) {
        // 1. Force a reward-index update with a **zero-value transfer**.
        //    Pendle refreshes reward integrals *only* inside the ERC-20 transfer
        //    hooks (`_beforeTokenTransfer/_afterTokenTransfer`). It exposes no
        //    public equivalent to Curve’s `user_checkpoint`. Sending a
        //    0-token transfer is therefore the cheapest permission-less way to
        //    ensure `userReward[locker].accrued` is current before we measure
        //    pending rewards in CHECKPOINT mode. The call moves no tokens
        //    and has zero economic impact.
        bytes memory ping = abi.encodeWithSelector(IERC20.transfer.selector, address(0xdEaD), 0);
        require(_executeTransaction(gauge, ping), CheckpointFailed());

        // 2. Return the freshly-updated accrued value
        uint128 accrued = IPendleGauge(gauge).userReward(REWARD_TOKEN, LOCKER).accrued;
        pendingRewards.feeSubjectAmount = accrued;
        pendingRewards.totalAmount = accrued;
    }

    /// @notice Deposit hook. Intentionally empty
    /// @dev    Holding the LP token inside the Locker is sufficient for it to start accruing rewards
    ///         because the token itself is a Gauge share. No on-chain interaction is necessary here.
    function _deposit(address, /* asset */ address, /* gauge */ uint256 /* amount */ ) internal override {}

    /// @notice Sends LP tokens from Locker to receiver
    /// @param asset     The LP token address
    /// @param ""        The Gauge. Unused but kept for interface compatibility
    /// @param amount    Amount of LP tokens to transfer
    /// @param receiver  Destination address that receives the LP tokens
    function _withdraw(address asset, address, uint256 amount, address receiver) internal override {
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, receiver, amount);
        require(_executeTransaction(asset, transferData), WithdrawFailed());
    }

    /// @notice Harvest **all** rewards from a Pendle market.
    /// @dev Harvests ALL rewards (PENDLE emissions + SY incentives).
    ///      Non-PENDLE tokens are immediately forwarded to rewardReceiver.
    ///      The returned `rewardAmount` consists of:
    ///        - PENDLE emissions distributed by GaugeController, plus
    ///        - any PENDLE that might be part of the SY incentive stream (extra rewards)
    /// @param gauge          Address of the Pendle market (also the embedded gauge).
    /// @return rewardAmount  Amount of PENDLE harvested
    function _harvestLocker(address gauge, bytes memory) internal override returns (uint256 rewardAmount) {
        uint256[] memory harvestedAmounts = IPendleMarket(gauge).redeemRewards(LOCKER);

        address[] memory rewardTokens = IPendleMarket(gauge).getRewardTokens();
        uint256 nbOfRewardTokens = rewardTokens.length;
        require(nbOfRewardTokens == harvestedAmounts.length, PendleRewardArraysLengthMismatch());

        address rewardReceiver = PROTOCOL_CONTROLLER.rewardReceiver(gauge);
        require(rewardReceiver != address(0), RewardReceiverNotSet());

        // Forward the extra (non-PENDLE) rewards to rewardReceiver
        bool hasExtraRewards;
        for (uint256 i; i < nbOfRewardTokens; i++) {
            address rewardToken = rewardTokens[i];
            uint256 harvested = harvestedAmounts[i];

            if (harvested == 0) continue;

            if (rewardToken == REWARD_TOKEN) {
                rewardAmount = harvested;
            } else {
                bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver, harvested);
                require(_executeTransaction(rewardToken, data), HarvestFailed());
                hasExtraRewards = true;
            }
        }

        // Tell the reward receiver to distribute the rewards
        if (hasExtraRewards) IRewardReceiver(rewardReceiver).distributeRewards();
    }
}
