// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/interfaces/IVeYFI.sol";
import "src/base/depositor/DepositorV4.sol";

/// @title YFIDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract YFIDepositor is DepositorV4 {
    address public constant VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;

    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorV4(_token, _locker, _minter, _gauge, 4 * 370 days)
    {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the amount.
            ILocker(locker).increaseAmount(_amount);

            uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

            IVeYFI.LockedBalance memory _lockedBalance = IVeYFI(VE_YFI).locked(address(locker));
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > _lockedBalance.end;

            if (_canIncrease) {
                /// Increase the unlock time.
                ILocker(locker).increaseUnlockTime(_unlockTime);
            }

            emit TokenLocked(msg.sender, _amount);
        }
    }
}
