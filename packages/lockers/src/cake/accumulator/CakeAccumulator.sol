// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/Accumulator.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {IRevenueSharingPool} from "src/base/interfaces/IRevenueSharingPool.sol";

/// @notice CAKE Accumulator.
/// @author StakeDAO
contract CAKEAccumulator is Accumulator {
    /// @notice CAKE token address
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    /// @notice Masterchef Strategy.
    address public constant MASTERCHEF_STRATEGY = 0x632418eC44Bf27478a3dfC3591f4c30fD8D012ab;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance) Accumulator(_gauge, CAKE, _locker, _governance) {
        SafeTransferLib.safeApprove(CAKE, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claim CAKE rewards for the locker and notify all to the LGV4
    /// @param revenueSharingPools pancake revenue sharing pools
    /// @param notifySDT if notify SDT or not
    function claimAndNotifyAll(address[] memory revenueSharingPools, bool, bool notifySDT, bool claimFeeStrategy)
        external
    {
        /// Claim Revenue Reward.
        ICakeLocker(locker).claimRevenue(revenueSharingPools);

        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        /// Notify the first revenue sharing pool.
        address tokenReward = IRevenueSharingPool(revenueSharingPools[0]).rewardToken();
        notifyReward(tokenReward, notifySDT, claimFeeStrategy);

        for (uint256 i = 1; i < revenueSharingPools.length;) {
            tokenReward = IRevenueSharingPool(revenueSharingPools[i]).rewardToken();
            if (tokenReward == rewardToken) continue;

            /// We don't want to pull from the fee splitter for the rest of the pools.
            notifyReward(tokenReward, false, false);

            unchecked {
                ++i;
            }
        }
    }

    function _claimFeeStrategy() internal override {
        IStrategy(strategy).claimNativeRewards();
        IStrategy(MASTERCHEF_STRATEGY).claimNativeRewards();
    }
}
