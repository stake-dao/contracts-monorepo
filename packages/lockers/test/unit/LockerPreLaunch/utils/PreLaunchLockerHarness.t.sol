// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {DepositorPreLaunch} from "src/DepositorPreLaunch.sol";
import {LockerPreLaunch} from "src/LockerPreLaunch.sol";

contract PreLaunchLockerHarness is LockerPreLaunch {
    constructor(address _token, address _sdToken, address _gauge, uint256 _customForceCancelDelay)
        LockerPreLaunch(_token, _sdToken, _gauge, _customForceCancelDelay)
    {}

    function _cheat_state(STATE _state) external {
        _setState(_state);
    }

    function _cheat_depositor(address _depositor) external {
        depositor = DepositorPreLaunch(_depositor);
    }
}
