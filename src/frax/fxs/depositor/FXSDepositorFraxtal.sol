// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "src/base/depositor/DepositorV4.sol";

/// @title Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FXSDepositorFraxtal is DepositorV4 {
    error CallFailed();

    constructor(
        address _token,
        address _locker,
        address _minter,
        address _gauge,
        address _delegationRegistry,
        address _initialDelegate
    ) DepositorV4(_token, _locker, _minter, _gauge, 4 * 365 days) {
        // Custom code for Fraxtal
        // set _initialDelegate as delegate
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        // disable self managing delegation
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
    }
}
