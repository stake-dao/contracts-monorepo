// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/locker/VeCRVLocker.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IZeroBaseLocker} from "src/common/interfaces/zerolend/IZeroBaseLocker.sol";
import {IOmnichainStakingBase} from "src/common/interfaces/zerolend/omnichainstaking/IOmnichainStakingBase.sol";

/// @title  Locker
/// @notice Locker contract for locking tokens for a period of time
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker {
    // TODO is it ok to add this?
    using SafeERC20 for IERC20;

    IZeroBaseLocker public immutable zeroLocker;

    uint256 public lockerTokenId;

    constructor(address _zeroLocker, address _governance, address _token, address _veToken)
        VeCRVLocker(_governance, _token, _veToken)
    {
        zeroLocker = IZeroBaseLocker(_zeroLocker);

        // TODO make sure this is safe, should be as the locker doesn't hold tokens, it's just a gateway
        IERC20(token).approve(address(veToken), type(uint256).max);
    }

    function name() public pure override returns (string memory) {
        return "ZERO Locker";
    }

    // TODO add natspecs
    // TODO analyze the risk of creating multiple lock tokens
    //      should this method only be called once?
    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        IERC20(token).safeApprove(address(zeroLocker), _value);

        // create the lock
        lockerTokenId = zeroLocker.createLock(_value, _unlockTime, true);

        emit LockCreated(_value, _unlockTime);
    }

    // TODO add natspecs
    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value > 0) {
            // IVeToken(veToken).increase_amount(_value);

            IOmnichainStakingBase(veToken).increaseLockAmount(lockerTokenId, _value);
        }

        if (_unlockTime > 0) {
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (zeroLocker.lockedEnd(lockerTokenId));

            if (_canIncrease) {
                // IVeToken(veToken).increase_unlock_time(_unlockTime);
                IOmnichainStakingBase(veToken).increaseLockDuration(lockerTokenId, _unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Claim the rewards from the fee distributor.
    /// @param _feeDistributor Address of the fee distributor.
    /// @param _token Address of the token to claim.
    /// @param _recipient Address to send the tokens to.
    function claimRewards(address _feeDistributor, address _token, address _recipient)
        external
        override
        onlyGovernanceOrAccumulator
    {
        IOmnichainStakingBase(_feeDistributor).getReward();

        if (_recipient != address(0)) {
            IERC20(_token).safeTransfer(_recipient, IERC20(_token).balanceOf(address(this)));
        }
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    /// @param _recipient Address to send the tokens to
    function release(address _recipient) external override onlyGovernance {
        // TODO
    }
}
