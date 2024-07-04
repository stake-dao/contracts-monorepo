// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @title FXTLDelegation
/// @notice Helper to delegate FXTL Points.
/// @author StakeDAO
contract FXTLDelegation {
    constructor(address _delegationRegistry, address _initialDelegate) {
        /// Set initial delegate.
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert("CallFailed");

        /// Disable self managing delegation.
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert("CallFailed");
    }
}
