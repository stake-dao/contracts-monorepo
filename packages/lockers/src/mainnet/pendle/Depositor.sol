// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/depositor/BaseDepositor.sol";
import {IVePendle} from "src/common/interfaces/IVePendle.sol";
import {IExecutor} from "src/common/interfaces/IExecutor.sol";
import {IPendleLocker} from "src/common/interfaces/IPendleLocker.sol";

/// @title BaseDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    /// @notice Address of the veCRV token.
    address public constant VE_PENDLE = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;

    constructor(address _token, address _locker, address _minter, address _gauge)
        BaseDepositor(_token, _locker, _minter, _gauge, 2 * 365 days)
    {}

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the lock.
            IPendleLocker(locker).increaseAmount(uint128(_amount));
        }

        /// Define the "new" unlock time.
        uint256 _unlockTime = (block.timestamp + MAX_LOCK_DURATION) / 1 weeks * 1 weeks;

        /// Get the current expiry of the lock.
        (, uint128 _expiry) = IVePendle(VE_PENDLE).positionData(locker);

        /// Define if the unlock time can be increased.
        bool _canIncrease = _unlockTime > _expiry;

        /// Increase the unlock time if the lock is not at the maximum duration.
        if (_canIncrease) {
            IPendleLocker(locker).increaseUnlockTime(uint128(_unlockTime));
        }
    }
}
