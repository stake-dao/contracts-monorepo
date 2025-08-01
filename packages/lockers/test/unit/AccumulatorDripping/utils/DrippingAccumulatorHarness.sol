// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {AccumulatorDripping} from "src/AccumulatorDripping.sol";

contract DrippingAccumulatorHarness is AccumulatorDripping {
    constructor(address _gauge, address _rewardToken, address _locker, address _governance, uint256 _periodLength)
        AccumulatorDripping(_gauge, _rewardToken, _locker, _governance, _periodLength)
    {}

    function _expose_startNewDistribution() external {
        startNewDistribution();
    }

    function _expose_advanceDistributionStep() external {
        advanceDistributionStep();
    }

    function _expose_calculateDistributableReward() external view returns (uint256) {
        return calculateDistributableReward();
    }

    function _expose_getCurrentWeekTimestamp() external view returns (uint256) {
        return getCurrentWeekTimestamp();
    }

    function _expose_getCurrentRewardTokenBalance() external view returns (uint256) {
        return getCurrentRewardTokenBalance();
    }
}
