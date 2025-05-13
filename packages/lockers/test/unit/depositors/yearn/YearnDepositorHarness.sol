// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {YearnDepositor} from "src/mainnet/yearn/Depositor.sol";

contract YearnDepositorHarness is YearnDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        YearnDepositor(_token, _locker, _minter, _gauge, _gateway)
    {}

    function _expose_lockToken(uint256 _amount) external {
        _lockToken(_amount);
    }
}
