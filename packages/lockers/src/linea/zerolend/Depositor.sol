// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {BaseDepositor, ITokenMinter, ILiquidityGauge} from "src/common/depositor/BaseDepositor.sol";
import {ILocker} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

import {Enum} from "@safe/contracts/libraries/Enum.sol";

/// @title Stake DAO ZERO Depositor
/// @notice Contract that accepts ZERO and locks them in the Locker, minting sdZERO in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    error ZeroValue();
    error ZeroLockDuration();
    error EmptyTokenIdList();
    error NotOwnerOfToken(uint256 tokenId);
    error ExecFromSafeModuleFailed();

    /// @notice Event emitted when a lock is created.
    /// @param value Amount of tokens locked.
    /// @param duration Duration of the lock.
    event LockCreated(uint256 value, uint256 duration);

    /// @notice Event emitted when a lock is increased.
    /// @param value Amount of tokens locked.
    /// @param duration Duration of the lock.
    event LockIncreased(uint256 value, uint256 duration);

    ILockerToken public immutable zeroLocker;

    /// @notice Address of the Voting Escrow contract.
    IZeroVp public immutable veToken;

    /// @notice Token ID of the locker ERC721 token representing the locked ZERO tokens.
    uint256 public zeroLockedTokenId;

    /// @notice Constructor
    /// @param _token ZERO token.
    /// @param _locker SD locker.
    /// @param _minter sdZERO token.
    /// @param _gauge sdZERO-gauge contract.
    /// @param _zeroLocker ZeroLend locker NFT contract.
    /// @param _veToken ZEROvp token.
    constructor(address _token, address _locker, address _minter, address _gauge, address _zeroLocker, address _veToken)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {
        zeroLocker = ILockerToken(_zeroLocker);
        veToken = IZeroVp(_veToken);
    }

    function _stakeNftTokenFromLocker(uint256 _tokenId) internal {
        (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", locker, veToken, _tokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    function _unstakeNftTokenFromLocker() internal {
        // Unstake zeroLockedTokenId.
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(veToken),
            0,
            abi.encodeWithSelector(IZeroVp.unstakeToken.selector, zeroLockedTokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    function _createZeroLock(uint256 _amount) internal returns (uint256 _tokenId) {
        (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSelector(ILockerToken.createLock.selector, _amount, MAX_LOCK_DURATION, false),
            Enum.Operation.Call
        );

        if (!_success) revert ExecFromSafeModuleFailed();

        _tokenId = abi.decode(_data, (uint256));
    }

    function _mergeWithZeroLockedToken(uint256 _tokenIdFrom, uint256 _tokenIdTo) internal {
        // Merge _tokenId with zeroLockedTokenId.
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSelector(ILockerToken.merge.selector, _tokenIdFrom, _tokenIdTo),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    /// @param _amount Amount of tokens to deposit.
    function _lockToken(uint256 _amount) internal virtual override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount == 0) revert ZeroValue();

        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

        uint256 _newZeroLockedTokenId = _createZeroLock(_amount);

        // If the locker was initialized, merge old token ID with new token ID.
        // Else, we just initialized the locker so we emit the event.
        if (zeroLockedTokenId != 0) {
            _unstakeNftTokenFromLocker();
            _mergeWithZeroLockedToken(zeroLockedTokenId, _newZeroLockedTokenId);
            emit LockIncreased(_amount, _unlockTime);
        } else {
            emit LockCreated(_amount, _unlockTime);
        }

        // Stake token in ZEROvp contract to receive voting power tokens.
        _stakeNftTokenFromLocker(_newZeroLockedTokenId);

        zeroLockedTokenId = _newZeroLockedTokenId;
    }

    /// @notice Call the SafeLocker to merge NFT tokens.
    /// @param _tokenIds Token IDs to deposit.
    function _lockerDeposit(uint256[] calldata _tokenIds) internal returns (uint256 _amount) {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        uint256 _lockEnd = zeroLocker.lockedEnd(zeroLockedTokenId);

        _unstakeNftTokenFromLocker();

        // Verify that _owner owns all tokenIds.
        for (uint256 index = 0; index < _tokenIds.length;) {
            // _owner must own all token IDs.
            if (zeroLocker.ownerOf(_tokenIds[index]) != msg.sender) revert NotOwnerOfToken(_tokenIds[index]);

            // Keep track of the merged amount.
            _amount += zeroLocker.locked(_tokenIds[index]).amount;

            // Merge user token into locker zeroLockedTokenId.
            _mergeWithZeroLockedToken(_tokenIds[index], zeroLockedTokenId);

            // Keep track of the maximum lock end time as it will be the lock end time of the merge result.
            uint256 _currentLockEnd = zeroLocker.lockedEnd(_tokenIds[index]);
            if (_currentLockEnd > _lockEnd) _lockEnd = _currentLockEnd;

            unchecked {
                ++index;
            }
        }

        // Put token back into staking.
        _stakeNftTokenFromLocker(zeroLockedTokenId);

        emit LockIncreased(_amount, _lockEnd);
    }

    /// @notice Deposit ZeroLend locker NFTs, and receive sdZero or sdZeroGauge in return.
    /// @param _tokenIds Token IDs to deposit.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user to receive the sdToken.
    /// @dev In order to allow the transfer of the NFT tokens, msg.sender needs to give an approvalForAll to the locker.
    /// If stake is true, sdZero tokens are staked in the gauge which distributes rewards. If stake is false,
    /// sdZero tokens are sent to the user.
    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external {
        if (_user == address(0)) revert ADDRESS_ZERO();

        uint256 _amount = _lockerDeposit(_tokenIds);

        // Mint sdtoken to the user if the gauge is not set.
        if (_stake && gauge != address(0)) {
            /// Mint sdToken to this contract.
            ITokenMinter(minter).mint(address(this), _amount);

            /// Deposit sdToken into gauge for _user.
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            /// Mint sdToken to _user.
            ITokenMinter(minter).mint(_user, _amount);
        }
    }
}
