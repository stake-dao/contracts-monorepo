// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {DepositorBase} from "./DepositorBase.sol";

/// @title DepositorPreLaunch
/// @notice A base contract for depositors that are used in pre-launch scenarios.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
/// @dev This contract is used to lock tokens in the Locker contract without minting the sdTokens.
///      The pre-launch locker is responsible for minting the sdTokens during the pre-launch period.
contract DepositorPreLaunch is DepositorBase {
    /// @notice The address of the pre launch locker.
    address public immutable preLaunchLocker;

    /// @notice Error thrown when the caller is not the pre-launch locker.
    error ONLY_PRE_LAUNCH_LOCKER();

    /// @notice Constructor for the DepositorPreLaunch.
    /// @param _token The address of the base token.
    /// @param _locker The address of the locker contract.
    /// @param _minter The address of the minter contract.
    /// @param _gauge The address of the gauge contract.
    /// @param _maxLockDuration The maximum lock duration.
    /// @param _preLaunchLocker The address of the pre-launch locker.
    /// @custom:reverts ADDRESS_ZERO if any of the addresses are zero.
    constructor(
        address _token,
        address _locker,
        address _minter,
        address _gauge,
        uint256 _maxLockDuration,
        address _preLaunchLocker
    ) DepositorBase(_token, _locker, _minter, _gauge, _maxLockDuration) {
        if (_preLaunchLocker == address(0)) revert ADDRESS_ZERO();
        preLaunchLocker = _preLaunchLocker;
    }

    /// @notice Initiate a lock in the Locker contract without minting the sdTokens.
    /// @param amount The amount of tokens to lock.
    /// @dev Can only be called by the pre-launch locker.
    /// @custom:reverts ONLY_PRE_LAUNCH_LOCKER if the caller is not the pre-launch locker.
    function createLock(uint256 amount) external override {
        if (msg.sender != preLaunchLocker) revert ONLY_PRE_LAUNCH_LOCKER();

        _createLockFrom(msg.sender, amount);
    }
}
