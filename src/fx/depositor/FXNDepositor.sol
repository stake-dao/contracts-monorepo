// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "src/base/depositor/DepositorV4.sol";

/// @title Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FXNDepositor is Depositor {
    constructor(address _token, address _locker, address _minter, address _gauge)
        Depositor(_token, _locker, _minter, _gauge)
    {}
}
