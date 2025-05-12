// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {DAO} from "address-book/src/dao/1.sol";
import {BalancerDepositor} from "src/mainnet/balancer/Depositor.sol";

contract BalancerDepositorHarness is BalancerDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        BalancerDepositor(_token, _locker, _minter, _gauge, _gateway)
    {}

    function _expose_lockToken(uint256 _amount) external {
        _lockToken(_amount);
    }
}
