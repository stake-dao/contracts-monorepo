// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchBaseDepositor} from "src/common/depositor/PreLaunchBaseDepositor.sol";
import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";

contract PreLaunchLockerHarness is PreLaunchLocker {
    constructor(address _token, address _sdToken, address _gauge, uint256 _customForceCancelDelay)
        PreLaunchLocker(_token, _sdToken, _gauge, _customForceCancelDelay)
    {}

    function _cheat_state(STATE _state) external {
        _setState(_state);
    }

    function _cheat_depositor(address _depositor) external {
        depositor = PreLaunchBaseDepositor(_depositor);
    }
}
