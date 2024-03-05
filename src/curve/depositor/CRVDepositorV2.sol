// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/interfaces/IExecutor.sol";
import "src/base/extension/CurveExchangeDepositor.sol";
import {IVeToken} from "src/base/interfaces/IVeToken.sol";

/// @title Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CRVDepositorV2 is CurveExchangeDepositor {
    /// @notice Address of the veCRV token.
    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    address public constant SD_VE_CRV = 0x478bBC744811eE8310B461514BDc29D03739084D;

    constructor(address _token, address _locker, address _minter, address _gauge, address _pool)
        CurveExchangeDepositor(_token, _locker, _minter, _gauge, 4 * 365 days, _pool)
    {}

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the lock.
            ILocker(locker).increaseAmount(_amount);

            uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVeToken(VE_CRV).locked__end(locker));

            /// Increase the unlock time if the lock is not at the maximum duration.
            if (_canIncrease) {
                IExecutor(locker).execute(
                    VE_CRV, 0, abi.encodeWithSignature("increase_unlock_time(uint256)", _unlockTime)
                );
            }

            emit TokenLocked(msg.sender, _amount);
        }
    }

    /// @notice Lock forever (irreversible action) old sdveCrv to sdCrv with 1:1 rate.
    /// @param _amount Amount to lock.
    function lockSdveCrvToSdCrv(uint256 _amount) external {
        IERC20(SD_VE_CRV).transferFrom(msg.sender, address(this), _amount);
        // mint new sdCrv to the user
        ITokenMinter(minter).mint(msg.sender, _amount);
    }
}
