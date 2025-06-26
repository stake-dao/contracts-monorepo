// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/DepositorBase.sol";

import {SafeModule} from "src/utils/SafeModule.sol";
import {IYieldNest} from "src/interfaces/IYieldNest.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Stake DAO YieldNest Depositor
/// @notice Contract responsible for managing sdYND token deposits, locking them in the Locker,
///         and minting sdYND tokens in return.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract YieldnestDepositor is DepositorBase, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The YieldNest escrow contract to deposit the tokens.
    address public constant ESCROW = YieldnestProtocol.ESCROW;

    /// @notice The YieldNest clock contract to get the next checkpoint timestamp.
    address public constant CLOCK = YieldnestProtocol.CLOCK;

    /// @notice The YieldNest prelaunch locker contract to deposit the tokens.
    address public constant PRELAUNCH_LOCKER = YieldnestProtocol.PRELAUNCH_LOCKER;

    /// @notice Array of token IDs for the tokens locked in the YieldNest
    uint256[] public tokenIds;

    /// @notice The last interval that the tokens were locked in the YieldNest
    uint256 lastInterval;

    /// @notice The delay between the last interval and the next interval where the tokens can be locked
    uint256 public preCheckpointWindow = 12 hours;

    /// @notice Error thrown when the tokens are already locked
    error TokensAlreadyLocked();

    /// @notice Error thrown when the function is called by a non-prelaunch locker
    error OnlyPrelaunchLocker();

    /// @notice Initializes the Depositor contract with required dependencies
    /// @param _token Address of the YND token
    /// @param _locker Address of the Stake DAO YieldNest Locker contract
    /// @param _minter Address of the sdYND minter contract
    /// @param _gauge Address of the sdYND-gauge contract
    /// @param _gateway Address of the gateway contract
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _token, address _locker, address _minter, address _gauge, address _gateway)
        DepositorBase(_token, _locker, _minter, _gauge, 0)
        SafeModule(_gateway)
    {
        /// Set the state of the contract to CANCELED
        _setState(STATE.CANCELED);
    }

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {
        require(tokenIds.length == 0, TokensAlreadyLocked());
        require(msg.sender == PRELAUNCH_LOCKER, OnlyPrelaunchLocker());

        /// 1. Transfer the tokens from the sender to the locker
        SafeTransferLib.safeTransferFrom(token, msg.sender, _getLocker(), _amount);

        /// 2. Max Approval of the token to the YieldNest Escrow
        _executeTransaction(token, abi.encodeWithSelector(IERC20.approve.selector, ESCROW, type(uint256).max));

        /// 3. Lock the tokens in the YieldNest
        /// @dev The amount is not used here because the sdTokens are already minted.
        _lockToken(0);

        /// Set the state of the contract to ACTIVE
        _setState(STATE.ACTIVE);
    }

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken(uint256 _amount) internal override {
        /// Get the next checkpoint timestamp
        uint256 nextInterval = IYieldNest(CLOCK).epochNextCheckpointTs();

        if (tokenIds.length > 0) {
            /// Skip if already locked for this checkpoint
          if (lastInterval == nextInterval) return;
          /// Only proceed if we're within 12 hours of checkpoint
          if (block.timestamp < nextInterval - preCheckpointWindow) return;
      }

        /// Check if there's any tokens to lock by comparing the total supply and the balance of the locker
        _amount += IERC20Metadata(minter).totalSupply() - getLockedBalance();
        if (_amount == 0) return;

        uint256 lastLockId = IYieldNest(ESCROW).lastLockId();

        /// Lock the tokens in the YieldNest
        _executeTransaction(ESCROW, abi.encodeWithSelector(IYieldNest.createLock.selector, _amount));

        /// Add the token ID to the array
        tokenIds.push(lastLockId + 1);

        /// Update the last interval
        lastInterval = nextInterval;
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the total locked balance of the tokens in the YieldNest
    /// @return totalLockedBalance The total locked balance of the tokens in the YieldNest
    function getLockedBalance() public view returns (uint256 totalLockedBalance) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IYieldNest.LockedBalance memory lockedBalance = IYieldNest(ESCROW).locked(tokenIds[i]);
            totalLockedBalance += lockedBalance.amount;
        }

        return totalLockedBalance;
    }

    function getTokenIds() external view returns (uint256[] memory) {
        return tokenIds;
    }

    function version() external pure virtual override returns (string memory) {
        return "2.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(YieldnestDepositor).name;
    }

    /// @notice Sets the pre-checkpoint window
    /// @param _preCheckpointWindow The new pre-checkpoint window
    function setPreCheckpointWindow(uint256 _preCheckpointWindow) external onlyGovernance {
        preCheckpointWindow = _preCheckpointWindow;
    }
}