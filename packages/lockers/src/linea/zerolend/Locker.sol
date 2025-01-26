// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/locker/VeCRVLocker.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

/// @title StakeDAO ZERO Locker
/// @notice Locker contract for locking ZERO tokens for a period of time.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker {
    using SafeERC20 for IERC20;

    error NotDepositor();
    error NotOwnerOfToken(uint256 tokenId);
    error EmptyTokenIdList();
    error CanOnlyBeCalledOnce();

    ILockerToken public immutable zeroLocker;

    /// @notice Token ID of the locker ERC721 token representing the locked ZERO tokens.
    uint256 public zeroLockedTokenId;

    /// @notice Constructor
    /// @param _zeroLocker ZeroLend locker NFT contract.
    /// @param _governance SD governance.
    /// @param _token ZERO token.
    /// @param _veToken ZEROvp token.
    constructor(address _zeroLocker, address _governance, address _token, address _veToken)
        VeCRVLocker(_governance, _token, _veToken)
    {
        zeroLocker = ILockerToken(_zeroLocker);
        IERC20(token).approve(address(veToken), type(uint256).max);
    }

    function name() public pure override returns (string memory) {
        // TODO confirm name
        return "ZERO Locker";
    }

    /// @notice Creates the  StakeDao lock.
    /// @param _value Value to be added to the locker as the initial locked ZERO amount.
    /// @param _unlockTime Duration of the initial lock.
    /// @dev Can only be called once.
    // TODO is it ok not to mint sdZERO for this initial lock?
    // TODO ok to limit to calling it just once?
    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (zeroLockedTokenId != 0) revert CanOnlyBeCalledOnce();

        IERC20(token).safeApprove(address(zeroLocker), _value);
        zeroLockedTokenId = zeroLocker.createLock(_value, _unlockTime, true);

        emit LockCreated(_value, _unlockTime);
    }

    /// @notice Increases the lock amount and/or lock duration of the locker token in the Voting Escrow contract.
    /// @param _value The amount of tokens to add to the existing lock.
    /// @param _unlockTime The new unlock time for the lock, in seconds since the epoch. Must be aligned to weeks.
    /// @custom:emits Emits a `LockIncreased` event on successful lock update.
    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value > 0) {
            IZeroVp(veToken).increaseLockAmount(zeroLockedTokenId, _value);
        }

        if (_unlockTime > 0) {
            // TODO should we extend every time? the voting power is based on lock's start and end not current time.
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (zeroLocker.lockedEnd(zeroLockedTokenId));

            if (_canIncrease) {
                IZeroVp(veToken).increaseLockDuration(zeroLockedTokenId, _unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Logic was migrated to the accumulator for more flexibility.
    function claimRewards(address, address, address) external view override onlyGovernanceOrAccumulator {}

    /// @notice Allows depositing other locked tokens which will increase the current lock.
    /// @param _owner Owner of the NFT tokens to deposit.
    /// @param _tokenIds NFT token IDs to deposit.
    /// @dev This contract needs to be approved by _owner in order for the NFTs to be merged with the zeroLockedTokenId token.
    /// @custom:emits Emits a `LockIncreased` event on successful lock update.
    function deposit(address _owner, uint256[] calldata _tokenIds)
        external
        onlyGovernanceOrDepositor
        returns (uint256 _amount)
    {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        uint256 _lockEnd = zeroLocker.lockedEnd(zeroLockedTokenId);

        // Unstake locker NFT token.
        IZeroVp(veToken).unstakeToken(zeroLockedTokenId);

        // Verify that _owner owns all tokenIds.
        for (uint256 index = 0; index < _tokenIds.length;) {
            // _owner must own all token IDs.
            if (zeroLocker.ownerOf(_tokenIds[index]) != _owner) revert NotOwnerOfToken(_tokenIds[index]);

            // Keep track of the merged amount.
            _amount += zeroLocker.locked(_tokenIds[index]).amount;

            // Merge user token into locker zeroLockedTokenId.
            zeroLocker.merge(_tokenIds[index], zeroLockedTokenId);

            // Keep track of the maximum lock end time as it will be the lock end time of the merge result.
            uint256 _currentLockEnd = zeroLocker.lockedEnd(_tokenIds[index]);
            if (_currentLockEnd > _lockEnd) _lockEnd = _currentLockEnd;

            unchecked {
                ++index;
            }
        }

        // Transfer the token back to the ZEROvp contract.
        zeroLocker.safeTransferFrom(address(this), veToken, zeroLockedTokenId);

        emit LockIncreased(_amount, _lockEnd);
    }

    /// @notice Release the tokens from the LockerToken contract when the lock expires.
    /// @param _recipient The address that will receive the ZERO tokens.
    // TODO it will be imposible to re create a lock, is this ok?
    function release(address _recipient) external override onlyGovernance {
        IZeroVp(veToken).unstakeToken(zeroLockedTokenId);
        ILockerToken(zeroLocker).withdraw(zeroLockedTokenId);

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, _balance);
    }

    /// @notice Execute an arbitrary transaction as the governance.
    /// @param to Address to send the transaction to.
    /// @param value Amount of ETH to send with the transaction.
    /// @param data Encoded data of the transaction.
    /// @dev Override to allow calling from the accumulator to claim rewards.
    function execute(address to, uint256 value, bytes calldata data)
        external
        payable
        override
        onlyGovernanceOrAccumulator
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = to.call{value: value}(data);
        return (success, result);
    }
}
