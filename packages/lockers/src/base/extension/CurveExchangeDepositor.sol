// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "src/base/depositor/Depositor.sol";
import "src/base/interfaces/ICurvePool.sol";

/// @title CurveExchange
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @dev Adapted for veCRV like Locker.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract CurveExchangeDepositor is Depositor {
    /// @notice Address of the sdToken pool.
    address public pool;

    /// @notice Event emitted when tokens are deposited.
    /// @param caller Address of the caller.
    /// @param user Address of the user.
    /// @param amount Amount of tokens deposited.
    /// @param stake Whether the sdToken is staked in the gauge.
    event Deposited(address indexed caller, address indexed user, uint256 amount, bool stake);

    /// Throwed when no enought minimum amount is met.
    error MIN_AMOUNT_NOT_MET();

    constructor(
        address _token,
        address _locker,
        address _minter,
        address _gauge,
        uint256 _maxLockDuration,
        address _pool
    ) Depositor(_token, _locker, _minter, _gauge, _maxLockDuration) {
        pool = _pool;

        /// Approve sdToken to gauge.
        if (_pool != address(0)) {
            SafeTransferLib.safeApprove(_token, _pool, type(uint256).max);
        }
    }

    /// @notice Deposit using the sdToken pool.
    /// @param _amount Amount of tokens to deposit.
    /// @param _minAmount Minimum amount of tokens to receive.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user.
    function deposit(uint256 _amount, uint256 _minAmount, bool _stake, address _user) public {
        if (_amount == 0) revert AMOUNT_ZERO();
        if (_user == address(0)) revert ADDRESS_ZERO();
        if (_minAmount < _amount) revert MIN_AMOUNT_NOT_MET();

        /// Transfer tokens from the user to the contract.
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), _amount);

        // Mint sdtoken to the user if the gauge is not set
        if (_stake && gauge != address(0)) {
            _amount = _swap(_amount, _minAmount, address(this));

            /// Deposit sdToken into gauge for _user.
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            _amount = _swap(_amount, _minAmount, _user);
        }

        emit Deposited(msg.sender, _user, _amount, _stake);
    }

    /// @notice Swap tokens using the sdToken pool.
    /// @param _amount Amount of tokens to swap.
    /// @param _minAmount Minimum amount of tokens to receive.
    /// @param _receiver Address of the receiver.
    function _swap(uint256 _amount, uint256 _minAmount, address _receiver) internal returns (uint256) {
        return ICurvePool(pool).exchange(0, 1, _amount, _minAmount, _receiver);
    }

    /// @notice Set the pool address.
    /// @param _pool Address of the sdToken pool
    function setPool(address _pool) external onlyGovernance {
        pool = _pool;

        /// Approve sdToken to gauge.
        if (_pool != address(0)) {
            SafeTransferLib.safeApprove(token, _pool, type(uint256).max);
        }
    }
}
