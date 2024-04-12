// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/base/locker/VeCRVLocker.sol";
import {IVestedFXS} from "src/base/interfaces/IVestedFXS.sol";

/// @title Locker
/// @notice Locks the FXS tokens to veFXS contract
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FxsLockerFraxtal is VeCRVLocker {
    using SafeERC20 for IERC20;

    error LockAlreadyCreated();

    constructor(address _governance, address _token, address _veToken) VeCRVLocker(_governance, _token, _veToken) {}

    /// @dev Returns the name of the locker.
    function name() public pure override returns (string memory) {
        return "FXS Locker";
    }

    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        // constrain the locker to create at most one lock
        if (IVestedFXS(veToken).nextId(address(this)) != 0) revert LockAlreadyCreated();

        IERC20(token).safeApprove(veToken, type(uint256).max);
        IVestedFXS(veToken).createLock(address(this), _value, uint128(_unlockTime));

        emit LockCreated(_value, _unlockTime);
    }

    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value != 0) {
            IVestedFXS(veToken).increaseAmount(_value, 0); // lock index = 0
        }

        if (_unlockTime != 0) {
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVestedFXS(veToken).lockedEnd(address(this), 0));

            if (_canIncrease) {
                IVestedFXS(veToken).increaseUnlockTime(uint128(_unlockTime), 0); // lock index = 0
            }
        }
    }

    function release(address _recipient) external override onlyGovernance {
        IVestedFXS(veToken).withdraw(0); // lock index = 0

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, _balance);
    }

    function claimRewards(address, address, address) external override onlyGovernanceOrAccumulator {}
}
