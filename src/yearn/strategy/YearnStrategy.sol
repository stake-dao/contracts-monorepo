// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Strategy} from "src/base/strategy/Strategy.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

/// @title Yearn Strategy
/// @author StakeDAO
/// @notice Deposit/Withdraw in yearn gauges
contract YearnStrategy is Strategy {
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function claim(address _asset) public override {
        /// Get the gauge address.
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        /// Cache the rewardDistributor address.
        address rewardDistributor = rewardDistributors[gauge];

        /// 1. Claim `rewardToken` from the Gauge.
        //uint256 _claimed = _claimRewardToken(gauge);
        IYearnGauge(gauge).getReward();
        // notify it via recevier ?

        /// 2. Distribute SDT
        // Distribute SDT to the related gauge
        ISDTDistributor(SDTDistributor).distribute(rewardDistributor);
    }

    function increaseUnlockTime(uint256 _value) external override onlyGovernance {
        locker.increaseUnlockTime(_value);
    }

    function release(address _recipient) external onlyGovernance {
        locker.release(_recipient);
    }

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewads() internal override {
        locker.claimRewards(rewardToken, accumulator);
    }
}
