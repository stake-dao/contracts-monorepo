// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Allocator} from "src/Allocator.sol";

/// @title PendleAllocator.
/// @notice Allocator that routes 100 % of LP tokens to the Locker
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org
contract PendleAllocator is Allocator {
    constructor(address _locker, address _gateway) Allocator(_locker, _gateway) {}
}
