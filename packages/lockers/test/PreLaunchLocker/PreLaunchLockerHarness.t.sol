// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {PreLaunchLocker} from "src/PreLaunchLocker.sol";

contract PreLaunchLockerHarness is PreLaunchLocker {
    constructor(address _token) PreLaunchLocker(_token) {}

    function _cheat_setState(STATE _state) external {
        _setState(_state);
    }
}
