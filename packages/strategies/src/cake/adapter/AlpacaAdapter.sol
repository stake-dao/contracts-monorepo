// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/base/interfaces/IAdapter.sol";
import "src/base/interfaces/IAlpacaReader.sol";
import "src/base/interfaces/IAlpacaManager.sol";

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Adapter for the Alpaca strategy.
contract AlpacaAdapter is Clone {
    /// @notice Address of the PCS V3 Alpaca Helper contract.
    address public constant READER = 0xb6556f9B6A97c465d2e3D6bfff8bcb28219B9972;

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
        require((_amount0 == 0) != (_amount1 == 0), "deposit: only support single token");

        (, uint256 sharePriceWithFee) = IAlpacaReader(READER).getVaultSharePrice(stakingToken());
        require(sharePriceWithFee > 0, "deposit: share price can't be zero");
        IAlpacaReader.VaultSummary memory summary = IAlpacaReader(READER).getVaultSummary(stakingToken());
        IAlpacaManager manager_ = IAlpacaManager(IAlpacaManager(stakingToken()).vaultManager());
        IAlpacaManager.TokenAmount[] memory depositParams = new IAlpacaManager.TokenAmount[](1);

        uint256 minAmount;
        if (_data.length > 0) {
            minAmount = abi.decode(_data, (uint256));
        }

        if (_amount0 > 0) {
            SafeTransferLib.safeTransferFrom(token0(), vault(), address(this), _amount0);
            SafeTransferLib.safeApproveWithRetry(token0(), address(manager_), _amount0);

            depositParams[0] = IAlpacaManager.TokenAmount({token: token0(), amount: _amount0});
            bytes memory result = manager_.deposit(vault(), stakingToken(), depositParams, minAmount);
            (uint256 usedAmount0,) = abi.decode(result, (uint256, uint256));
            _share = usedAmount0 * summary.token0price / sharePriceWithFee;

            if (ERC20(token0()).balanceOf(address(this)) > 0) {
                SafeTransferLib.safeTransfer(token0(), _user, ERC20(token0()).balanceOf(address(this)));
            }
        } else if (_amount1 > 0) {
            SafeTransferLib.safeTransferFrom(token1(), vault(), address(this), _amount1);
            SafeTransferLib.safeApproveWithRetry(token1(), address(manager_), _amount1);

            depositParams[0] = IAlpacaManager.TokenAmount({token: token1(), amount: _amount1});
            bytes memory result = manager_.deposit(vault(), stakingToken(), depositParams, minAmount);
            (, uint256 usedAmount1) = abi.decode(result, (uint256, uint256));
            _share = usedAmount1 * summary.token1price / sharePriceWithFee;

            if (ERC20(token1()).balanceOf(address(this)) > 0) {
                SafeTransferLib.safeTransfer(token1(), _user, ERC20(token1()).balanceOf(address(this)));
            }
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
        IAlpacaManager manager_ = IAlpacaManager(IAlpacaManager(stakingToken()).vaultManager());
        IAlpacaManager.TokenAmount[] memory minAmountOuts = new IAlpacaManager.TokenAmount[](2);
        (uint256 minAmount0, uint256 minAmount1) = abi.decode(_data, (uint256, uint256));
        minAmountOuts[0] = IAlpacaManager.TokenAmount({token: token0(), amount: minAmount0});
        minAmountOuts[1] = IAlpacaManager.TokenAmount({token: token1(), amount: minAmount1});

        SafeTransferLib.safeTransferFrom(vault(), stakingToken(), address(this), _share);

        SafeTransferLib.safeApproveWithRetry(stakingToken(), address(manager_), _share);

        IAlpacaManager.TokenAmount[] memory amountOuts = manager_.withdraw(stakingToken(), _share, minAmountOuts);
        _amount0 = amountOuts[0].amount;
        _amount1 = amountOuts[1].amount;

        SafeTransferLib.safeTransfer(token0(), _user, _amount0);
        SafeTransferLib.safeTransfer(token1(), _user, _amount1);

        if (ERC20(stakingToken()).balanceOf(address(this)) > 0) {
            SafeTransferLib.safeTransfer(stakingToken(), _user, _amount1);
        }
    }
}
