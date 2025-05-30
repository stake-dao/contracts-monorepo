// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/DepositorBase.sol";

/// @title DepositorBase
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is DepositorBase {
    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorBase(_token, _locker, _minter, _gauge, 4 * 365 days)
    {}
}
