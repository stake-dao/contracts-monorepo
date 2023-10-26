// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Strategy} from "src/base/strategy/Strategy.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";

/// @title Yearn Strategy
/// @author StakeDAO
/// @notice Deposit/Withdraw in yearn gauges
contract YearnStrategy is Strategy {

    mapping(address => address) public rewardReceivers; // sdGauge -> rewardReceiver

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function harvest(address _asset, bool _distributeSDT, bool _claimExtra) public override {
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

    function setRewardReceiver(address _gauge, address _rewardReceiver) external onlyGovernanceOrAllowed {
        rewardReceivers[_gauge] = _rewardReceiver;
    }

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewads() internal override {
        locker.claimRewards(rewardToken, accumulator);
    }

    function _withdrawFromLocker(address _asset, address _gauge, uint256 _amount) internal override {
        /// Withdraw from the Gauge trough the Locker.
        locker.execute(_gauge, 0, abi.encodeWithSignature("withdraw(uint256,address,address)", _amount, address(this), address(locker)));
    }
    


}
