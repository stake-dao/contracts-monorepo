// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/locker/VeCRVLocker.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IZeroBaseLocker} from "src/common/interfaces/zerolend/IZeroBaseLocker.sol";
import {IOmnichainStakingBase} from "src/common/interfaces/zerolend/omnichainstaking/IOmnichainStakingBase.sol";

/// @title  Locker
/// @notice Locker contract for locking tokens for a period of time
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker {
    using SafeERC20 for IERC20;

    IZeroBaseLocker public immutable zeroLocker;

    // TODO rename
    uint256 public lockerTokenId;

    error NotDepositor();
    error NotOwnerOfToken(uint256 tokenId);

    constructor(address _zeroLocker, address _governance, address _token, address _veToken)
        VeCRVLocker(_governance, _token, _veToken)
    {
        zeroLocker = IZeroBaseLocker(_zeroLocker);
        IERC20(token).approve(address(veToken), type(uint256).max);
    }

    function name() public pure override returns (string memory) {
        return "ZERO Locker";
    }

    // TODO add natspecs
    // TODO analyze the risk of creating multiple lock tokens
    //      should this method only be called once?
    function createLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        IERC20(token).safeApprove(address(zeroLocker), _value);

        // create the lock
        lockerTokenId = zeroLocker.createLock(_value, _unlockTime, true);

        emit LockCreated(_value, _unlockTime);
    }

    // TODO add natspecs
    function increaseLock(uint256 _value, uint256 _unlockTime) external override onlyGovernanceOrDepositor {
        if (_value > 0) {
            IOmnichainStakingBase(veToken).increaseLockAmount(lockerTokenId, _value);
        }

        if (_unlockTime > 0) {
            bool _canIncrease = (_unlockTime / 1 weeks * 1 weeks) > (zeroLocker.lockedEnd(lockerTokenId));

            if (_canIncrease) {
                IOmnichainStakingBase(veToken).increaseLockDuration(lockerTokenId, _unlockTime);
            }
        }

        emit LockIncreased(_value, _unlockTime);
    }

    /// @notice Claim the rewards from the fee distributor.
    function claimRewards(address, address, address) external view override onlyGovernanceOrAccumulator {
        // migrated this code to the Accumulator for more flexibility
        revert();
    }

    function deposit(address _owner, uint256[] calldata _tokenIds) external returns (uint256 _amount) {
        if (msg.sender != depositor) revert NotDepositor();

        // unstake locker NFT token
        IOmnichainStakingBase(veToken).unstakeToken(lockerTokenId);

        // verify that msg.sender owns all tokenIds
        for (uint256 index = 0; index < _tokenIds.length;) {
            if (zeroLocker.ownerOf(_tokenIds[index]) != _owner) revert NotOwnerOfToken(_tokenIds[index]);

            _amount += zeroLocker.locked(_tokenIds[index]).amount;

            // merge user token into locker token
            zeroLocker.merge(_tokenIds[index], lockerTokenId);

            unchecked {
                ++index;
            }
        }

        // transfer the token back to the ZEROvp contract
        zeroLocker.safeTransferFrom(address(this), veToken, lockerTokenId);
    }

    /// @notice Release the tokens from the Voting Escrow contract when the lock expires.
    // TODO natspecs dev
    function release(address) external view override onlyGovernance {
        // prefer using release(address _recipient, uint256 _tokenId)
        revert();
    }

    // TODO natspecs
    function release(address _recipient, uint256 _tokenId) external onlyGovernance {
        // Someone could send a locker NFT to this contract, losing it in the process. This function
        // would make sure any token owned by this contract can be withdrawn.
        if (IZeroBaseLocker(zeroLocker).ownerOf(_tokenId) == veToken) {
            IOmnichainStakingBase(veToken).unstakeToken(_tokenId);
        }
        IZeroBaseLocker(zeroLocker).withdraw(_tokenId);

        uint256 _balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(_recipient, _balance);

        emit Released(msg.sender, _balance);
    }

    /// @notice Execute an arbitrary transaction as the governance.
    /// @dev Override to allow calling from the accumulator to claim rewards.
    /// @param to Address to send the transaction to.
    /// @param value Amount of ETH to send with the transaction.
    /// @param data Encoded data of the transaction.
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
