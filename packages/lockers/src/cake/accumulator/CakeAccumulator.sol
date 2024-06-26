// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/Accumulator.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {IRevenueSharingPool} from "src/base/interfaces/IRevenueSharingPool.sol";

/// @notice A contract that accumulates CAKE rewards and notifies them to the sdCAKE gauge
/// @author StakeDAO
contract CakeAccumulator is Accumulator {
    /// @notice CAKE token address
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _daoFeeRecipient dao fee recipient
    /// @param _liquidityFeeRecipient liquidity fee recipient
    /// @param _governance governance
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _governance
    ) Accumulator(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient, _governance) {
        SafeTransferLib.safeApprove(CAKE, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claim CAKE rewards for the locker and notify all to the LGV4
    /// @param _revenueSharingPools pancake revenue sharing pools
    /// @param _notifySDT if notify SDT or not
    /// @param _pullFromFeeSplitter if pull tokens from the fee splitter or not
    function claimAndNotifyAll(address[] memory _revenueSharingPools, bool _notifySDT, bool _pullFromFeeSplitter)
        external
    {
        /// Claim Revenue Reward.
        ICakeLocker(locker).claimRevenue(_revenueSharingPools);

        /// Notify the first revenue sharing pool.
        address tokenReward = IRevenueSharingPool(_revenueSharingPools[0]).rewardToken();
        notifyReward(tokenReward, _notifySDT, _pullFromFeeSplitter);

        for (uint256 i = 1; i < _revenueSharingPools.length;) {
            tokenReward = IRevenueSharingPool(_revenueSharingPools[i]).rewardToken();

            /// We don't want to pull from the fee splitter for the rest of the pools.
            notifyReward(tokenReward, false, false);

            unchecked {
                ++i;
            }
        }
    }
}
