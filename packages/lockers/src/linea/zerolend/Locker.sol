// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/locker/VeCRVLocker.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

/// @title  Locker
/// @notice Locker contract for locking tokens for a period of time.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker {
    using SafeERC20 for IERC20;

    ILockerToken public immutable zeroLocker;

    uint256 public zeroLockedTokenId;

    error NotDepositor();
    error NotOwnerOfToken(uint256 tokenId);
    error EmptyTokenIdList();
    error CanOnlyBeCalledOnce();

    constructor(address _zeroLocker, address _governance, address _token, address _veToken)
        VeCRVLocker(_governance, _token, _veToken)
    {
        zeroLocker = ILockerToken(_zeroLocker);
        IERC20(token).approve(address(veToken), type(uint256).max);
    }

    function name() public pure override returns (string memory) {
        return "ZERO Locker";
    }

    /// @notice Creates the  StakeDao lock. Should only be called once.
    /// @param _value value to be added to the locker as the initial locked ZERO amount.
    /// @param _unlockTime duration of the initial lock.
    /// @dev Should only be called once.
    // TODO is it ok not to mint sdZERO for this initial lock?
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
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (zeroLocker.lockedEnd(zeroLockedTokenId));

            if (_canIncrease) {
                IZeroVp(veToken).increaseLockDuration(zeroLockedTokenId, _unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Logic was migrated to the accumulator for more flexibility.
    function claimRewards(address, address, address) external view override onlyGovernanceOrAccumulator {}

    /// @notice Allows depositing a new
    /// @param _owner Owner of the NFT tokens IDs.
    /// @param _tokenIds NFT token IDs to deposit.
    /// @dev This contract needs to be approved by the _owner in order for the NFTs to be merged with the zeroLockedTokenId.
    function deposit(address _owner, uint256[] calldata _tokenIds)
        external
        onlyGovernanceOrDepositor
        returns (uint256 _amount)
    {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        // unstake locker NFT token
        IZeroVp(veToken).unstakeToken(zeroLockedTokenId);

        // verify that _owner owns all tokenIds
        for (uint256 index = 0; index < _tokenIds.length;) {
            if (zeroLocker.ownerOf(_tokenIds[index]) != _owner) revert NotOwnerOfToken(_tokenIds[index]);

            _amount += zeroLocker.locked(_tokenIds[index]).amount;

            // merge user token into locker token
            zeroLocker.merge(_tokenIds[index], zeroLockedTokenId);

            unchecked {
                ++index;
            }
        }

        // Transfer the token back to the ZEROvp contract.
        zeroLocker.safeTransferFrom(address(this), veToken, zeroLockedTokenId);
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    /// @dev    Prefer using release(address _recipient, uint256 _tokenId).
    function release(address) external view override onlyGovernance {}

    /// @notice Releases ZERO tokens from the Voting Escrow contract when the lock on a token ID expires.
    /// @param _recipient The address that will receive the ZERO tokens.
    /// @param _tokenId The ID of the NFT token to unstake.
    /// @dev Someone could send a locker NFT to this contract, losing it in the process.
    /// This function ensures any token owned by this contract can be withdrawn.
    function release(address _recipient, uint256 _tokenId) external onlyGovernance {
        if (ILockerToken(zeroLocker).ownerOf(_tokenId) == veToken) {
            IZeroVp(veToken).unstakeToken(_tokenId);
        }
        ILockerToken(zeroLocker).withdraw(_tokenId);

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
