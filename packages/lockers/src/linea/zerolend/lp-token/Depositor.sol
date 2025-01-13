// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/depositor/BaseDepositor.sol";

/// @title BaseDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge)
        BaseDepositor(_token, _locker, _minter, _gauge, 1 * 365 days)
    {}
}
