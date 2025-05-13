// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {PendleDepositor} from "src/mainnet/pendle/Depositor.sol";

contract PendleDepositorHarness is PendleDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        PendleDepositor(_token, _locker, _minter, _gauge, _gateway)
    {}

    function _expose_lockToken(uint256 _amount) external {
        _lockToken(_amount);
    }
}
