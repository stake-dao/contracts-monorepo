// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/base/interfaces/IAdapter.sol";
import "src/base/interfaces/IDefiEdgeStrategy.sol";

import {Clone} from "solady/src/utils/Clone.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @notice Adapter for the DEdge strategy.
contract DEdgeAdapter is Clone {
    /// @notice Address of the vault.
    function vault() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice Address of the staking token.
    function stakingToken() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice Address of token0 required to mint LP tokens.
    function token0() public pure returns (address) {
        return _getArgAddress(40);
    }

    /// @notice Address of token1 required to mint LP tokens.
    function token1() public pure returns (address) {
        return _getArgAddress(60);
    }

    /// Throwed when the caller is not the vault.
    error NOT_VAULT();

    modifier onlyVault() {
        if (msg.sender != vault()) revert NOT_VAULT();
        _;
    }

    constructor() {
        SafeTransferLib.safeApproveWithRetry(token0(), stakingToken(), type(uint256).max);
        SafeTransferLib.safeApproveWithRetry(token1(), stakingToken(), type(uint256).max);
    }

    /// @notice Mint staking token and return them to the vault in order to deposit them into the strategy.
    /// @param _amount0 Amount of token0 to deposit.
    /// @param _amount1 Amount of token1 to deposit.
    /// @param _user Address to receive the receipt tokens.
    /// @param _data Data to pass to the adapter, such as minimum amounts, slippage protection, etc.
    function deposit(uint256 _amount0, uint256 _amount1, address _user, bytes calldata _data)
        external
        onlyVault
        returns (uint256 _share)
    {
        SafeTransferLib.safeTransferFrom(token0(), vault(), address(this), _amount0);
        SafeTransferLib.safeTransferFrom(token1(), vault(), address(this), _amount1);

        uint256 amount0Used;
        uint256 amount1Used;
        if (_data.length > 0) {
            (uint256 amount0Min, uint256 amount1Min, uint256 minShare) = abi.decode(_data, (uint256, uint256, uint256));
            (amount0Used, amount1Used, _share) =
                IDefiEdgeStrategy(stakingToken()).mint(_amount0, _amount1, amount0Min, amount1Min, minShare);
        } else {
            (amount0Used, amount1Used, _share) = IDefiEdgeStrategy(stakingToken()).mint(_amount0, _amount1, 0, 0, 0);
        }

        SafeTransferLib.safeTransfer(stakingToken(), vault(), _share);

        if (ERC20(token0()).balanceOf(address(this)) > 0) {
            SafeTransferLib.safeTransfer(token0(), _user, ERC20(token0()).balanceOf(address(this)));
        }
        if (ERC20(token1()).balanceOf(address(this)) > 0) {
            SafeTransferLib.safeTransfer(token1(), _user, ERC20(token1()).balanceOf(address(this)));
        }
    }

    /// @notice Withdraw staking token and burn them for the underlying tokens.
    /// @param _share Amount of staking token to withdraw.
    /// @param _user Address to receive the underlying tokens.
    /// @param _data Data to pass to the adapter, such as minimum amounts, slippage protection, etc.
    function withdraw(uint256 _share, address _user, bytes calldata _data)
        external
        onlyVault
        returns (uint256 _amount0, uint256 _amount1)
    {
        SafeTransferLib.safeTransferFrom(stakingToken(), vault(), address(this), _share);

        if (_data.length > 0) {
            (uint256 amount0Min, uint256 amount1Min) = abi.decode(_data, (uint256, uint256));
            (_amount0, _amount1) = IDefiEdgeStrategy(stakingToken()).burn(_share, amount0Min, amount1Min);
        } else {
            (_amount0, _amount1) = IDefiEdgeStrategy(stakingToken()).burn(_share, 0, 0);
        }

        SafeTransferLib.safeTransfer(token1(), _user, ERC20(token1()).balanceOf(address(this)));
        SafeTransferLib.safeTransfer(token0(), _user, ERC20(token0()).balanceOf(address(this)));

        if (ERC20(stakingToken()).balanceOf(address(this)) > 0) {
            SafeTransferLib.safeTransfer(stakingToken(), _user, ERC20(stakingToken()).balanceOf(address(this)));
        }
    }
}
