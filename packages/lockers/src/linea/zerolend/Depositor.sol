// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {BaseDepositor, ITokenMinter, ILiquidityGauge} from "src/common/depositor/BaseDepositor.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/stakedao/ISdZeroLocker.sol";
import {ILocker} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

// TODO make Safe module

/// @title Stake DAO ZERO Depositor
/// @notice Contract that accepts ZERO and locks them in the Locker, minting sdZERO in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    // TODO does it work for encodeWithSelector?? I'm not sure
    using SafeERC20 for IERC20;

    error ZeroValue();
    error ZeroLockDuration();
    error EmptyTokenIdList();
    error NotOwnerOfToken(uint256 tokenId);

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
    constructor(address _token, address _locker, address _minter, address _gauge, address _zeroLocker, address _veToken)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {
        zeroLocker = ILockerToken(_zeroLocker);

        veToken = IZeroVp(_veToken);

        // TODO execute it on safeLocker
        // IERC20(token).approve(address(zeroLocker), type(uint256).max);
    }

    // TODO implement increaseLock from executeFromModule calls here
    // TODO natspecs
    function _lockerIncreaseLock(uint256 _value, uint256 _lockDuration) internal {
        if (_value == 0) revert ZeroValue();
        if (_lockDuration == 0) revert ZeroLockDuration();

        uint256 _newZeroLockedTokenId;
        {
            uint256 _unlockTime = block.timestamp + _lockDuration;

            (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                address(zeroLocker),
                0,
                abi.encodeWithSelector(ILockerToken.createLock.selector, _value, _lockDuration, false),
                Enum.Operation.Call
            );

            if (!_success) revert(); // TODO custom revert

            _newZeroLockedTokenId = abi.decode(_data, (uint256));
        }

        // If the locker was initialized, merge old token ID with new token ID.
        // Else, we just initialized the locker so we emit the event.
        if (zeroLockedTokenId != 0) {
            // veToken.unstakeToken(zeroLockedTokenId);
            {
                (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                    address(veToken),
                    0,
                    abi.encodeWithSelector(IZeroVp.unstakeToken.selector, zeroLockedTokenId),
                    Enum.Operation.Call
                );
                if (!_success) revert(); // TODO custom error
            }
            {
                (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                    address(zeroLocker),
                    0,
                    abi.encodeWithSelector(ILockerToken.merge.selector, zeroLockedTokenId, _newZeroLockedTokenId),
                    Enum.Operation.Call
                );
                if (!_success) revert(); // TODO custom error
            }
            // TODO emit LockIncreased(_value, _unlockTime);
        } else {
            // TODO emit LockCreated(_value, _unlockTime);
        }

        // stake token in ZEROvp contract to receive voting power tokens
        {
            (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                address(zeroLocker),
                0,
                // TODO convert to encodeWithSelector
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256)", locker, veToken, _newZeroLockedTokenId
                ),
                Enum.Operation.Call
            );
            if (!_success) revert(); // TODO custom error
        }

        zeroLockedTokenId = _newZeroLockedTokenId;
    }

    // TODO implement deposit from executeFromModule calls here

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal virtual override {
        // If there is Token available in the contract transfer it to the locker
        if (_amount != 0) {
            /// Increase the lock.
            _lockerIncreaseLock(_amount, MAX_LOCK_DURATION);
        }
    }

    function _lockerDeposit(uint256[] calldata _tokenIds) internal returns (uint256 _amount) {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        uint256 _lockEnd;
        {
            (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                address(zeroLocker),
                0,
                abi.encodeWithSelector(ILockerToken.lockedEnd.selector, zeroLockedTokenId),
                Enum.Operation.Call
            );

            if (!_success) revert(); // TODO custom revert

            _lockEnd = abi.decode(_data, (uint256));
        }

        {
            (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                address(veToken),
                0,
                abi.encodeWithSelector(IZeroVp.unstakeToken.selector, zeroLockedTokenId),
                Enum.Operation.Call
            );

            if (!_success) revert(); // TODO custom revert
        }

        // Verify that _owner owns all tokenIds.
        for (uint256 index = 0; index < _tokenIds.length;) {
            // _owner must own all token IDs.
            if (zeroLocker.ownerOf(_tokenIds[index]) != msg.sender) revert NotOwnerOfToken(_tokenIds[index]);

            // Keep track of the merged amount.
            _amount += zeroLocker.locked(_tokenIds[index]).amount;

            // Merge user token into locker zeroLockedTokenId.
            {
                (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                    address(zeroLocker),
                    0,
                    // TODO convert to encodeWithSelector
                    abi.encodeWithSelector(ILockerToken.merge.selector, _tokenIds[index], zeroLockedTokenId),
                    Enum.Operation.Call
                );

                if (!_success) revert(); // TODO custom revert
            }

            // Keep track of the maximum lock end time as it will be the lock end time of the merge result.
            uint256 _currentLockEnd = zeroLocker.lockedEnd(_tokenIds[index]);
            if (_currentLockEnd > _lockEnd) _lockEnd = _currentLockEnd;

            unchecked {
                ++index;
            }
        }

        // put token back into staking
        {
            (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
                address(zeroLocker),
                0,
                // TODO convert to encodeWithSelector
                abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", locker, veToken, zeroLockedTokenId),
                Enum.Operation.Call
            );

            if (!_success) revert(); // TODO custom revert
        }

        // emit LockIncreased(_amount, _lockEnd);
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

        uint256 _amount = _lockerDeposit(_tokenIds); // ISdZeroLocker(locker).deposit(msg.sender, _tokenIds);

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
