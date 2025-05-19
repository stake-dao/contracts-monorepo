// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";

contract BaseAccumulatorHarness is BaseAccumulator {
    constructor(address _gauge, address _rewardToken, address _locker, address _governance)
        BaseAccumulator(_gauge, _rewardToken, _locker, _governance)
    {}

    function _expose_claimAccumulatedFee() external {
        return _claimAccumulatedFee();
    }

    function _expose_chargeFee(address _token, uint256 _amount) external returns (uint256 _charged) {
        return _chargeFee(_token, _amount);
    }
}
