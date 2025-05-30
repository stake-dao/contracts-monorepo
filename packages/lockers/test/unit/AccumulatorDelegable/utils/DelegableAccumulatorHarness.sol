// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AccumulatorDelegable} from "src/AccumulatorDelegable.sol";

contract DelegableAccumulatorHarness is AccumulatorDelegable {
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
    )
        AccumulatorDelegable(
            _gauge,
            _rewardToken,
            _locker,
            _governance,
            _token,
            _veToken,
            _veBoost,
            _veBoostDelegation,
            _multiplier
        )
    {}

    function _expose_shareWithDelegation() external returns (uint256 delegationShare) {
        return _shareWithDelegation();
    }
}
