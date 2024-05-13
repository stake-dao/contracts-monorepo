// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/base/vault/Vault.sol";
import "src/base/interfaces/IAdapter.sol";
import "src/base/interfaces/IAdapterRegistry.sol";

/// @dev Support mint/burn of PositionManager LP tokens, and other wrapped staking tokens.
contract ALMDepositorVault is Vault {
    //////////////////////////////////////////////////////
    /// --- ALM IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Address of the ALM Adapter registry.
    function registry() public pure returns (address _registry) {
        return _getArgAddress(60);
    }

    /// @notice Thrown when the adapter is not found.
    error NO_ADAPTER();

    /// @notice Mint staking token and deposit them into the strategy.
    /// @param _amount0 Amount of token0 to deposit.
    /// @param _amount1 Amount of token1 to deposit.
    /// @param _data Data to pass to the adapter, such as minimum amounts, slippage protection, etc.
    /// @param _receiver Address to receive the receipt tokens.
    function mintThenDeposit(uint256 _amount0, uint256 _amount1, bytes calldata _data, address _receiver) external {
        /// If no adapter is found, revert. Use the regular deposit function.
        address adapter = IAdapterRegistry(registry()).getAdapter(address(this));
        if (adapter == address(0)) revert NO_ADAPTER();

        /// We check for amount0 and amount1 to avoid unnecessary approvals, and because the adapter may not need both.
        if (_amount0 > 0) {
            address _token0 = IAdapter(adapter).token0();
            SafeTransferLib.safeTransferFrom(_token0, msg.sender, address(this), _amount0);
            SafeTransferLib.safeApproveWithRetry(_token0, adapter, _amount0);
        }

        if (_amount1 > 0) {
            address _token1 = IAdapter(adapter).token1();
            SafeTransferLib.safeTransferFrom(_token1, msg.sender, address(this), _amount1);
            SafeTransferLib.safeApproveWithRetry(_token1, adapter, _amount1);
        }

        /// Deposit the amount into the adapter and get the amount of staking tokens minted to deposit.
        uint256 _amount = IAdapter(adapter).deposit(_amount0, _amount1, msg.sender, _data);

        /// Deposit the amount into the strategy.
        _earn();

        /// Mint amount equivalent to the amount deposited.
        _mint(address(this), _amount);

        /// Deposit for the receiver in the reward distributor gauge.
        liquidityGauge().deposit(_amount, _receiver);
    }

    /// @notice Withdraw staking token and burn them for the underlying tokens.
    /// @param _amount Amount of staking token to withdraw.
    /// @param _data Data to pass to the adapter, such as minimum amounts, slippage protection, etc.
    /// @param _receiver Address to receive the underlying tokens.
    function withdrawThenBurn(uint256 _amount, bytes calldata _data, address _receiver) external {
        /// If no adapter is found, revert. Use the regular withdraw function.
        address adapter = IAdapterRegistry(registry()).getAdapter(address(this));
        if (adapter == address(0)) revert NO_ADAPTER();

        ///  Withdraw from the reward distributor gauge.
        liquidityGauge().withdraw(_amount, msg.sender, true);

        /// Burn vault shares.
        _burn(address(this), _amount);

        ///  Subtract the incentive token amount from the total amount or the next earn will dilute the shares.
        uint256 _tokenBalance = token().balanceOf(address(this)) - incentiveTokenAmount;

        /// Withdraw from the strategy if no enough tokens in the contract.
        if (_amount > _tokenBalance) {
            uint256 _toWithdraw = _amount - _tokenBalance;

            strategy().withdraw(address(token()), _toWithdraw);
        }

        SafeTransferLib.safeApproveWithRetry(address(token()), adapter, _amount);
        IAdapter(adapter).withdraw(_amount, _receiver, _data);
    }
}
