// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "solady/src/utils/SafeTransferLib.sol";
import {Enum} from "@safe/contracts/Safe.sol";

import {ILocker} from "src/common/interfaces/spectra/stakedao/ILocker.sol";
import {ISpectraLocker} from "src/common/interfaces/spectra/spectra/ISpectraLocker.sol";
import {BaseDepositor, ITokenMinter, ILiquidityGauge} from "src/common/depositor/BaseDepositor.sol";

/// @title Stake DAO Spectra Depositor
/// @notice Contract responsible for managing SPECTRA token deposits, locking them in the Locker,
///         and minting sdSPECTRA tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    ///////////////////////////////////////////////////////////////
    /// --- STATE VARIABLES & CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Spectra locker NFT contract interface
    ISpectraLocker public immutable spectraLocker;

    /// @notice Token ID representing the locked SPECTRA tokens in the locker ERC721
    uint256 public spectraLockedTokenId;

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    error ZeroValue();
    error ZeroAddress();
    error EmptyTokenIdList();
    error LockAlreadyExists();
    error NotOwnerOfToken(uint256 tokenId);
    error ExecFromSafeModuleFailed();

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when a new lock is creadted
    /// @param value Additional amount of tokens locked
    /// @param duration New duration of the lock in seconds
    event LockCreated(uint256 value, uint256 duration);

    /// @notice Emitted when an existing lock is increased
    /// @param value Additional amount of tokens locked
    /// @param duration New duration of the lock in seconds
    event LockIncreased(uint256 value, uint256 duration);

    ////////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Initializes the Depositor contract with required dependencies
    /// @param _token Address of the SPECTRA token
    /// @param _locker Address of the SD locker contract
    /// @param _minter Address of the sdSPECTRA minter contract
    /// @param _gauge Address of the sdSPECTRA-gauge contract
    /// @param _spectraLocker Address of the Spectra locker NFT contract
    constructor(address _token, address _locker, address _minter, address _gauge, address _spectraLocker)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {
        if (_spectraLocker == address(0)) {
            revert ZeroAddress();
        }

        spectraLocker = ISpectraLocker(_spectraLocker);
    }

    ////////////////////////////////////////////////////////////////
    /// --- BASE CONTRACT OVERRIDE
    ///////////////////////////////////////////////////////////////

    /// @notice Locks tokens held by the contract
    /// @dev Overrides BaseDepositor's _lockToken function
    /// @param _amount Amount of tokens to lock
    function _lockToken(uint256 _amount) internal virtual override {
        if (_amount == 0) revert ZeroValue();

        if (spectraLockedTokenId != 0) {
            _addTokensToNft(spectraLockedTokenId, _amount);
            emit LockIncreased(_amount, MAX_LOCK_DURATION);
        } else {
            _createLock(_amount);
            emit LockCreated(_amount, MAX_LOCK_DURATION);
        }
    }

    /// @notice Initiate a lock in the Locker contract.
    /// @param _amount Amount of tokens to lock.
    function createLock(uint256 _amount) external virtual override {
        /// Transfer tokens to locker contract
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(locker), _amount);

        _createLock(_amount);

        /// Mint sdToken to msg.sender.
        ITokenMinter(minter).mint(msg.sender, _amount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- NFT DEPOSIT FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits Spectra locker NFTs and mints sdSPECTRA or sdSPECTRA-gauge tokens
    /// @param _tokenIds Array of token IDs to deposit
    /// @param _stake If true, stakes sdToken in gauge; if false, sends to user
    /// @param _user Address to receive the sdToken
    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external {
        if (_user == address(0)) revert ADDRESS_ZERO();

        uint256 _amount = _mergeLocks(_tokenIds);

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
    function _mergeLocks(uint256[] calldata _tokenIds) internal returns (uint256 _amount) {
        if (_tokenIds.length == 0) revert EmptyTokenIdList();

        for (uint256 index = 0; index < _tokenIds.length;) {
            if (spectraLocker.ownerOf(_tokenIds[index]) != msg.sender) revert NotOwnerOfToken(_tokenIds[index]);

            ISpectraLocker.LockedBalance memory lockedBalance = spectraLocker.locked(_tokenIds[index]);
            if (lockedBalance.isPermanent) {
                // The Locked permanently tokens can't be merged
                _unlockPermanent(_tokenIds[index]);
            }
            _amount += lockedBalance.amount;

            _merge(_tokenIds[index], spectraLockedTokenId);

            unchecked {
                ++index;
            }
        }

        uint256 _lockEnd = block.timestamp + MAX_LOCK_DURATION;
        emit LockIncreased(_amount, _lockEnd);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Locks _amount of tokens into the designed NFT
    /// @param _tokenId ID of the veNFT to add tokens to
    /// @param _amount Amount of tokens to lock
    function _addTokensToNft(uint256 _tokenId, uint256 _amount) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(spectraLocker),
            0,
            abi.encodeWithSelector(ISpectraLocker.depositFor.selector, _tokenId, _amount),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice Merges two lock positions
    /// @param _tokenIdFrom Source token ID to merge from
    /// @param _tokenIdTo Destination token ID to merge into
    function _merge(uint256 _tokenIdFrom, uint256 _tokenIdTo) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(spectraLocker),
            0,
            abi.encodeWithSelector(ISpectraLocker.merge.selector, _tokenIdFrom, _tokenIdTo),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice unlocks the permanent status of a veNFT
    /// @param _tokenId token ID to unlock
    function _unlockPermanent(uint256 _tokenId) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(spectraLocker),
            0,
            abi.encodeWithSelector(ISpectraLocker.unlockPermanent.selector, _tokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice locks the permanent status of a veNFT
    /// @param _tokenId token ID to unlock
    function _lockPermanent(uint256 _tokenId) internal {
        (bool _success,) = ILocker(locker).execTransactionFromModuleReturnData(
            address(spectraLocker),
            0,
            abi.encodeWithSelector(ISpectraLocker.lockPermanent.selector, _tokenId),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();
    }

    /// @notice Creates initial lock for the locker
    /// @param _amount token ID to unlock
    function _createLock(uint256 _amount) internal {
        if (spectraLockedTokenId != 0) revert LockAlreadyExists();

        (bool _success, bytes memory newTokenId) = ILocker(locker).execTransactionFromModuleReturnData(
            address(spectraLocker),
            0,
            abi.encodeWithSelector(ISpectraLocker.createLock.selector, _amount, MAX_LOCK_DURATION),
            Enum.Operation.Call
        );
        if (!_success) revert ExecFromSafeModuleFailed();

        spectraLockedTokenId = abi.decode(newTokenId, (uint256));
        _lockPermanent(spectraLockedTokenId);
    }
}
