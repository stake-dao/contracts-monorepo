// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SpectraProtocol} from "address-book/src/SpectraBase.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ITokenMinter, ILiquidityGauge} from "src/DepositorBase.sol";
import {DepositorBase} from "src/DepositorBase.sol";
import {ISpectraRewardsDistributor} from "src/interfaces/ISpectraRewardsDistributor.sol";
import {ISpectraVoter} from "src/interfaces/ISpectraVoter.sol";
import {IVENFTSpectra} from "src/interfaces/IVENFTSpectra.sol";
import {SafeModule} from "src/utils/SafeModule.sol";

/// @title Stake DAO Spectra Depositor
/// @notice Contract responsible for managing SPECTRA token deposits, locking them in the Locker,
///         and minting sdSPECTRA tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is DepositorBase, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- STATE VARIABLES & CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Spectra locker NFT contract interface
    IVENFTSpectra public constant VE_NFT = IVENFTSpectra(SpectraProtocol.VENFT);

    /// @notice Spectra rewards distributor
    ISpectraRewardsDistributor public constant spectraRewardDistributor =
        ISpectraRewardsDistributor(SpectraProtocol.FEE_DISTRIBUTOR);

    /// @notice Token ID representing the locked SPECTRA tokens in the locker ERC721
    uint256 public spectraLockedTokenId;

    /// @notice Accumulator used to distribute rewards
    address public accumulator;

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    error ZeroValue();
    error ZeroAddress();
    error EmptyTokenIdList();
    error LockAlreadyExists();
    error AccumulatorNotSet();
    error NotOwnerOfToken(uint256 tokenId);

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when a new lock is created
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
    /// @dev The locker is also the gateway
    /// @param _token Address of the SPECTRA token
    /// @param _locker Address of the SD locker contract
    /// @param _minter Address of the sdSPECTRA minter contract
    /// @param _gauge Address of the sdSPECTRA-gauge contract
    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorBase(_token, _locker, _minter, _gauge, 4 * 365 days)
        SafeModule(_locker)
    {}

    ////////////////////////////////////////////////////////////////
    /// --- BASE CONTRACT OVERRIDE
    ///////////////////////////////////////////////////////////////

    /// @notice Locks tokens held by the contract
    /// @dev Overrides DepositorBase's _lockToken function
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

        // Mint sdToken to this contract and stake in gauge
        ITokenMinter(minter).mint(address(this), _amount);
        ILiquidityGauge(gauge).deposit(_amount, msg.sender);
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

        for (uint256 index; index < _tokenIds.length;) {
            if (VE_NFT.ownerOf(_tokenIds[index]) != msg.sender) revert NotOwnerOfToken(_tokenIds[index]);

            // Reset votes of the veNFT
            if (VE_NFT.voted(_tokenIds[index])) {
                _resetVotes(_tokenIds[index]);
            }

            // Trigger rebase of the veNFT
            if (spectraRewardDistributor.claimable(_tokenIds[index]) > 0) {
                spectraRewardDistributor.claim(_tokenIds[index]);
            }

            IVENFTSpectra.LockedBalance memory lockedBalance = VE_NFT.locked(_tokenIds[index]);
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
    /// --- REWARD FUNCTION
    ///////////////////////////////////////////////////////////////

    /// @notice mints rewards from rebasing and transfer them to the accumulator
    function mintRewards() public {
        if (accumulator == address(0)) revert AccumulatorNotSet();

        // Check the difference between sdToken supply and tokens locked
        uint256 sdTokenSupply = IERC20(minter).totalSupply();
        uint256 locked = VE_NFT.locked(spectraLockedTokenId).amount;

        uint256 rewardAmount = locked - sdTokenSupply;

        if (rewardAmount != 0) {
            // Mint difference from rebasing to the accumulator
            ITokenMinter(minter).mint(accumulator, rewardAmount);
        }
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Locks _amount of tokens into the designed NFT
    /// @param _tokenId ID of the veNFT to add tokens to
    /// @param _amount Amount of tokens to lock
    function _addTokensToNft(uint256 _tokenId, uint256 _amount) internal {
        _executeTransaction(
            address(VE_NFT), abi.encodeWithSelector(IVENFTSpectra.depositFor.selector, _tokenId, _amount)
        );
    }

    /// @notice Merges two lock positions
    /// @param _tokenIdFrom Source token ID to merge from
    /// @param _tokenIdTo Destination token ID to merge into
    function _merge(uint256 _tokenIdFrom, uint256 _tokenIdTo) internal {
        _executeTransaction(
            address(VE_NFT), abi.encodeWithSelector(IVENFTSpectra.merge.selector, _tokenIdFrom, _tokenIdTo)
        );
    }

    /// @notice unlocks the permanent status of a veNFT
    /// @param _tokenId token ID to unlock
    function _unlockPermanent(uint256 _tokenId) internal {
        _executeTransaction(address(VE_NFT), abi.encodeWithSelector(IVENFTSpectra.unlockPermanent.selector, _tokenId));
    }

    /// @notice locks the permanent status of a veNFT
    /// @param _tokenId token ID to unlock
    function _lockPermanent(uint256 _tokenId) internal {
        _executeTransaction(address(VE_NFT), abi.encodeWithSelector(IVENFTSpectra.lockPermanent.selector, _tokenId));
    }

    /// @notice Creates initial lock for the locker
    /// @param _amount token ID to unlock
    function _createLock(uint256 _amount) internal {
        if (spectraLockedTokenId != 0) revert LockAlreadyExists();

        bytes memory newTokenId = _executeTransaction(
            address(VE_NFT), abi.encodeWithSelector(IVENFTSpectra.createLock.selector, _amount, MAX_LOCK_DURATION)
        );

        spectraLockedTokenId = abi.decode(newTokenId, (uint256));
        _lockPermanent(spectraLockedTokenId);
    }

    /// @notice Resets votes of a veNFT
    /// @param _tokenId token ID to reset
    function _resetVotes(uint256 _tokenId) internal {
        _executeTransaction(
            address(VE_NFT.voter()), abi.encodeWithSelector(ISpectraVoter.reset.selector, address(VE_NFT), _tokenId)
        );
    }

    ////////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Sets accumulator address
    /// @param _accumulator address of the new accumulator
    function setAccumulator(address _accumulator) external onlyGovernance {
        accumulator = _accumulator;
    }
}
