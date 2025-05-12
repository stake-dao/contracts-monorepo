// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {DAO} from "address-book/src/dao/1.sol";
import {CurveDepositor} from "src/mainnet/curve/Depositor.sol";

contract CurveDepositorHarness is CurveDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        CurveDepositor(_token, _locker, _minter, _gauge, _gateway)
    {}

    function _expose_lockToken(uint256 _amount) external {
        _lockToken(_amount);
    }
}
