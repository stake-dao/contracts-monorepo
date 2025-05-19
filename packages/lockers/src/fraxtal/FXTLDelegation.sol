// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title FXTLDelegation
/// @notice Helper to delegate FXTL Points.
/// @author StakeDAO
contract FXTLDelegation {
    /// @notice Throwed on FXTL delegation failure
    error FXTLDelegationFailed();

    constructor(address _delegationRegistry, address _initialDelegate) {
        /// Set initial delegate.
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert FXTLDelegationFailed();

        /// Disable self managing delegation.
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert FXTLDelegationFailed();
    }
}
