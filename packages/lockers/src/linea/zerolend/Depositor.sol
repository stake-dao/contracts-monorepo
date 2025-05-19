// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Enum} from "@safe/contracts/common/Enum.sol";
import {BaseDepositor, ITokenMinter, ILiquidityGauge} from "src/common/depositor/BaseDepositor.sol";
import {ILocker} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {ILockerToken} from "src/common/interfaces/zerolend/zerolend/ILockerToken.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

/// @title Stake DAO ZERO Depositor
/// @notice Contract responsible for managing ZERO token deposits, locking them in the Locker,
///         and minting sdZERO tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    ///////////////////////////////////////////////////////////////
    /// --- STATE VARIABLES & CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice ZeroLend locker NFT contract interface
    ILockerToken public immutable zeroLocker;

    /// @notice Voting Escrow contract interface for managing voting power
    IZeroVp public immutable veToken;

    /// @notice Token ID representing the locked ZERO tokens in the locker ERC721
    uint256 public zeroLockedTokenId;

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    error ZeroValue();
    error ZeroAddress();
    error EmptyTokenIdList();
    error NotOwnerOfToken(uint256 tokenId);
    error ExecFromSafeModuleFailed();

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when an existing lock is increased
    /// @param value Additional amount of tokens locked
    /// @param duration New duration of the lock in seconds
    event LockIncreased(uint256 value, uint256 duration);

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Initializes the Depositor contract with required dependencies
    /// @param _token Address of the ZERO token
    /// @param _locker Address of the SD locker contract
    /// @param _minter Address of the sdZERO minter contract
    /// @param _gauge Address of the sdZERO-gauge contract
    /// @param _zeroLocker Address of the ZeroLend locker NFT contract
    /// @param _veToken Address of the ZEROvp token contract
    constructor(address _token, address _locker, address _minter, address _gauge, address _zeroLocker, address _veToken)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {
        if (_zeroLocker == address(0) || _veToken == address(0)) {
            revert ZeroAddress();
        }

        zeroLocker = ILockerToken(_zeroLocker);
        veToken = IZeroVp(_veToken);
    }

    ////////////////////////////////////////////////////////////////
    /// --- BASE CONTRACT OVERRIDE
    ///////////////////////////////////////////////////////////////

    /// @notice Locks tokens held by the contract
    /// @dev Overrides BaseDepositor's _lockToken function
    /// @param _amount Amount of tokens to lock
    function _lockToken(uint256 _amount) internal virtual override {
        if (_amount == 0) revert ZeroValue();

        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;
        uint256 _newZeroLockedTokenId = _createLock(_amount);

        if (zeroLockedTokenId != 0) {
            _unstakeNFTFromLocker();
            _merge(zeroLockedTokenId, _newZeroLockedTokenId);
            emit LockIncreased(_amount, _unlockTime);
        }

        _stakeNFTFromLocker(_newZeroLockedTokenId);
        zeroLockedTokenId = _newZeroLockedTokenId;
    }

    /// @notice Creates a new lock in the ZeroLend locker
    /// @dev Executes the lock creation through the Safe module
    /// @param _amount Amount of tokens to lock
    /// @return _tokenId ID of the newly created lock
    function _createLock(uint256 _amount) internal returns (uint256 _tokenId) {
        (bool _success, bytes memory _data) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSelector(ILockerToken.createLock.selector, _amount, MAX_LOCK_DURATION, false),
            Enum.Operation.Call
        );

        if (!_success) revert ExecFromSafeModuleFailed();
        _tokenId = abi.decode(_data, (uint256));
    }

    /// @notice Merges two lock positions
    /// @param _tokenIdFrom Source token ID to merge from
    /// @param _tokenIdTo Destination token ID to merge into
    function _merge(uint256 _tokenIdFrom, uint256 _tokenIdTo) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSelector(ILockerToken.merge.selector, _tokenIdFrom, _tokenIdTo),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice Unstakes the current locked token from ZEROvp
    function _unstakeNFTFromLocker() internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(veToken),
            0,
            abi.encodeWithSelector(IZeroVp.unstakeToken.selector, zeroLockedTokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice Stakes an NFT in the ZEROvp contract
    /// @param _tokenId Token ID to stake
    function _stakeNFTFromLocker(uint256 _tokenId) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(zeroLocker),
            0,
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", locker, veToken, _tokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    ////////////////////////////////////////////////////////////////
    /// --- NFT DEPOSIT FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits ZeroLend locker NFTs and mints sdZero or sdZeroGauge tokens
    /// @param _tokenIds Array of token IDs to deposit
    /// @param _stake If true, stakes sdToken in gauge; if false, sends to user
    /// @param _user Address to receive the sdToken
    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external {
        if (_user == address(0)) revert ADDRESS_ZERO();

        uint256 _amount = _mergeLocksAndStake(_tokenIds);

        if (_stake && gauge != address(0)) {
            // Mint sdToken to this contract and stake in gauge
            ITokenMinter(minter).mint(address(this), _amount);
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            // Mint sdToken directly to user
            ITokenMinter(minter).mint(_user, _amount);
        }
    }

    /// @notice Merges multiple locks and stakes the resulting token
    /// @param _tokenIds Array of token IDs to merge
    /// @return _amount Total amount of tokens merged
    function _mergeLocksAndStake(uint256[] calldata _tokenIds) internal returns (uint256 _amount) {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        _unstakeNFTFromLocker();

        for (uint256 index = 0; index < _tokenIds.length;) {
            if (zeroLocker.ownerOf(_tokenIds[index]) != msg.sender) revert NotOwnerOfToken(_tokenIds[index]);

            _amount += zeroLocker.locked(_tokenIds[index]).amount;
            _merge(_tokenIds[index], zeroLockedTokenId);

            unchecked {
                ++index;
            }
        }

        _stakeNFTFromLocker(zeroLockedTokenId);

        uint256 _lockEnd = zeroLocker.lockedEnd(zeroLockedTokenId);
        emit LockIncreased(_amount, _lockEnd);
    }
}
