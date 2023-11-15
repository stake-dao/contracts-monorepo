// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {VeCRVLocker} from "src/base/locker/VeCRVLocker.sol";
import {ICakeDepositor} from "src/base/interfaces/ICakeDepositor.sol";
import {IVeCake} from "src/base/interfaces/IVeCake.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

/// @title PancakeSwap Locker
/// @author StakeDAO
/// @notice Locks the CAKE tokens to veCAKE contract
contract CakeLocker is VeCRVLocker {
    error VE_TOKEN();

    modifier onlyVeCake() {
        if (msg.sender != veToken) revert VE_TOKEN();
        _;
    }

    /// @notice Constructor
    /// @param _governance governance
    /// @param _token token to lock
    /// @param _veToken veToken
    constructor(address _governance, address _token, address _veToken) VeCRVLocker(_governance, _token, _veToken) {}

    /// @dev Returns the name of the locker.
    function name() public pure override returns (string memory) {
        return "veCAKE Locker";
    }

    /// @notice Create a lock for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        SafeTransferLib.safeApprove(token, veToken, type(uint256).max);

        IVeCake(veToken).createLock(_value, _unlockTime);

        emit LockCreated(_value, _unlockTime);
    }

    /// @notice Increase the lock amount or duration for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value > 0) {
            IVeCake(veToken).increaseLockAmount(_value);
        }

        if (_unlockTime > 0) {
            (, uint256 lockedEndTime,,,,,,) = IVeCake(veToken).getUserInfo(address(this));
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > lockedEndTime;

            if (_canIncrease) {
                IVeCake(veToken).increaseUnlockTime(_unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    /// @param _recipient Address to send the tokens to
    function release(address _recipient) external override onlyGovernance {
        (int128 amount,,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(this));

        IVeCake(veToken).withdrawAll(_recipient);

        emit Released(msg.sender, uint256(uint128(amount)));
    }

    /// @notice Delegate CAKE to the locker, it has called during the user delegation
    /// @param _user user that delegated CAKE token
    /// @param _amount amount delegated
    function delegate(address _user, uint256 _amount, uint256) external onlyVeCake {
        // mint sdCAKE for the user and stake to the sdCAKE gauge
        ICakeDepositor(depositor).mintForCakeDelegator(_user, _amount);
    }
}
