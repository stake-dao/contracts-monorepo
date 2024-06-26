// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/depositor/DepositorV4.sol";

/// @title MAVDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @dev Adapted for Maverick Voting Escrow.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract MAVDepositor is DepositorV4 {
    using SafeERC20 for IERC20;

    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorV4(_token, _locker, _minter, _gauge, 4 * 365 days)
    {}

    function _lockToken(uint256 _amount) internal override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the lock.
            ILocker(locker).increaseLock(_amount, MAX_LOCK_DURATION);

            emit TokenLocked(msg.sender, _amount);
        }
    }

    /// @notice Initiate a lock in the Locker contract.
    /// @param _amount Amount of tokens to lock.
    function createLock(uint256 _amount) external override {
        /// Transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(locker), _amount);

        /// Can be called only once.
        ILocker(locker).createLock(_amount, MAX_LOCK_DURATION);

        /// Mint sdToken to msg.sender.
        ITokenMinter(minter).mint(msg.sender, _amount);

        emit CreateLock(_amount, MAX_LOCK_DURATION);
    }
}
