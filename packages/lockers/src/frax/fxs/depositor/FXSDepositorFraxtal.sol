// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "src/base/depositor/Depositor.sol";
import {ISdTokenOperator} from "src/base/interfaces/ISdTokenOperator.sol";

/// @title Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FXSDepositorFraxtal is Depositor {
    using SafeERC20 for IERC20;

    /// @notice Throwed when a low level call fails
    error CallFailed();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _token Address of the token
    /// @param _minter Address of the minter (on fraxtal it is the main operator)
    /// @param _gauge Address of the sdToken gauge
    /// @param _mainOperator Address of the main operator (the minter)
    /// @param _delegationRegistry Address of the fraxtal delegation registry
    /// @param _initialDelegate Address of the delegate that receives network reward
    constructor(
        address _token,
        address _locker,
        address _minter,
        address _gauge,
        address _mainOperator,
        address _delegationRegistry,
        address _initialDelegate
    ) Depositor(_token, _locker, _minter, _gauge, 4 * 365 days) {
        // Custom code for Fraxtal
        // set _initialDelegate as delegate
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        // disable self managing delegation
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();

        // set the minter as main operator
        minter = _mainOperator;
    }

    /// @notice Set the gauge to deposit sdToken
    /// @param _gauge gauge address
    function setGauge(address _gauge) external override onlyGovernance {
        gauge = _gauge;
        if (_gauge != address(0)) {
            /// Approve sdToken to gauge.
            IERC20(ISdTokenOperator(minter).sdToken()).safeApprove(gauge, type(uint256).max);
        }
    }

    /// @notice Set the operator for sdToken (leave it empty because on fraxtal the depositor is not the sdToken's operator)
    function setSdTokenMinterOperator(address) external override onlyGovernance {}
}
