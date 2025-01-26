// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IZeroLocker} from "src/common/interfaces/zerolend/zerolend/IZeroLocker.sol";

/**
 *   @title Voting Escrow
 *   @author Curve Finance
 *   @notice Votes have a weight depending on time, so that users are
 *   committed to the future of (whatever they are voting for)
 *   @dev Vote weight decays linearly over time. Lock time cannot be
 *   more than `MAXTIME` (4 years).
 *
 *   # Voting escrow to have time-weighted votes
 *   # Votes have a weight depending on time, so that users are committed
 *   # to the future of (whatever they are voting for).
 *   # The weight in this implementation is linear, and lock cannot be more than maxtime:
 *   # w ^
 *   # 1 +        /
 *   #   |      /
 *   #   |    /
 *   #   |  /
 *   #   |/c
 *   # 0 +--------+------> time
 *   # maxtime (4 years?)
 */
interface ILockerToken is IZeroLocker {
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId User NFT
    /// @return Epoch time of the lock end
    function lockedEnd(uint256 _tokenId) external view returns (uint256);

    /// @dev Returns the voting power of the `_owner`.
    ///      Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    /// @param _owner Address for whom to query the voting power of.
    function votingPowerOf(address _owner) external view returns (uint256 _power);

    function merge(uint256 _from, uint256 _to) external override;

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function depositFor(uint256 _tokenId, uint256 _value) external override;

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to, bool _stakeNFT)
        external
        override
        returns (uint256);

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _stakeNFT Should we also stake the NFT as well?
    function createLock(uint256 _value, uint256 _lockDuration, bool _stakeNFT) external override returns (uint256);

    /// @notice Deposit `_value` additional tokens for `_tokenId` without modifying the unlock time
    /// @param _value Amount of tokens to deposit and add to the lock
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    /// @notice Extend the unlock time for `_tokenId`
    /// @param _lockDuration New number of seconds until tokens unlock
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;

    /// @notice Withdraw all tokens for `_tokenId`
    /// @dev Only possible if the lock has expired
    function withdraw(uint256 _tokenId) external;

    function withdraw(uint256[] calldata _tokenIds) external;

    function withdraw(address _user) external;

    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    function tokenURI(uint256) external view returns (string memory);
}
