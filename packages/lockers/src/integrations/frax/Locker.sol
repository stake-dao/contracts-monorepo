// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVestedFXS} from "src/interfaces/IVestedFXS.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldDistributor} from "src/interfaces/IYieldDistributor.sol";
import {VeCRVLocker} from "src/integrations/curve/VeCRVLocker.sol";
import {FXTLDelegation} from "src/integrations/frax/FXTLDelegation.sol";

/// @title Locker
/// @notice Locks the FXS tokens to veFXS contract
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker, FXTLDelegation {
    using SafeERC20 for IERC20;

    /// @notice Throws if the lock is already created.
    error LockAlreadyCreated();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _governance Address of the governance
    /// @param _token Address of the token to lock
    /// @param _veToken Address of the veToken
    /// @param _delegationRegistry Address of the fraxtal delegation registry
    /// @param _initialDelegate Address of the delegate that receives network reward
    constructor(
        address _governance,
        address _token,
        address _veToken,
        address _delegationRegistry,
        address _initialDelegate
    ) VeCRVLocker(_governance, _token, _veToken) FXTLDelegation(_delegationRegistry, _initialDelegate) {}

    /// @dev Returns the name of the locker.
    function name() public pure override returns (string memory) {
        return "FXS Locker";
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Creates a lock by locking FXS token in the veFXS contract for the specified time
    /// @dev Can only be called by governance or depositor
    /// @param _value The amount of token to be locked
    /// @param _unlockTime The duration for which the token is to be locked
    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        // constrain the locker to create at most one lock
        if (IVestedFXS(veToken).nextId(address(this)) != 0) revert LockAlreadyCreated();

        IERC20(token).forceApprove(veToken, type(uint256).max);
        IVestedFXS(veToken).createLock(address(this), _value, uint128(_unlockTime));

        emit LockCreated(_value, _unlockTime);
    }

    /// @notice Increase the lock amount or duration for the contract on the Voting Escrow contract.
    /// @param _value Amount of tokens to lock
    /// @param _unlockTime Duration of the lock
    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value != 0) {
            IVestedFXS(veToken).increaseAmount(_value, 0); // lock index = 0
        }

        if (_unlockTime != 0) {
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (IVestedFXS(veToken).lockedEnd(address(this), 0));

            if (_canIncrease) {
                IVestedFXS(veToken).increaseUnlockTime(uint128(_unlockTime), 0); // lock index = 0
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Withdraw the FXS from veFXS
    /// @dev call only after lock time expires
    /// @param _recipient The address which will receive the released FXS
    function release(address _recipient) external override onlyGovernance {
        IVestedFXS(veToken).withdraw(0); // lock index = 0

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, _balance);
    }

    /// @notice Claim the rewards from the yield distributor.
    /// @param _yieldDistributor Address of the yield distributor.
    /// @param _token Address of the token to claim and transfer.
    /// @param _recipient Address to send the tokens to.
    function claimRewards(address _yieldDistributor, address _token, address _recipient)
        external
        override
        onlyGovernanceOrAccumulator
    {
        uint256 snapshotBalance = IERC20(_token).balanceOf(address(this));

        IYieldDistributor(_yieldDistributor).getYield();

        uint256 yield = IERC20(_token).balanceOf(address(this)) - snapshotBalance;

        if (yield != 0) {
            IERC20(_token).transfer(_recipient, yield);
        }
    }
}
