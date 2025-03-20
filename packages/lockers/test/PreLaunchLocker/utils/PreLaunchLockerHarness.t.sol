// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/common/locker/PreLaunchLocker.sol";

contract PreLaunchLockerHarness is PreLaunchLocker {
    constructor(address _token, address _sdToken, address _gauge) PreLaunchLocker(_token, _sdToken, _gauge) {}

    function _cheat_setState(STATE _state) external {
        _setState(_state);
    }
}
