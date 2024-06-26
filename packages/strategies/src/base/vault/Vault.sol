// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {IStrategy} from "src/base/interfaces/IStrategy.sol";
import {ISDLiquidityGauge} from "src/base/interfaces/ISDLiquidityGauge.sol";

/// @title Vault Implementation for Stake DAO.
/// @notice This contract allows users to deposit LP tokens into Stake DAO and receive sdGauge tokens in return.
/// @dev Is an ERC20 Token and Clonable.
contract Vault is ERC20, Clone {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice The denominator used for percentage calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice A small fee charged to incentivize the next call to the earn function.
    uint256 public constant EARN_INCENTIVE_FEE = 10;

    /// @notice The total amount of the incentive token.
    uint256 public incentiveTokenAmount;

    /// @dev Error thrown if the sender does not have enough tokens.
    error NOT_ENOUGH_TOKENS();

    /// @dev Error thrown if the contract has already been initialized.
    error ALREADY_INITIALIZED();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Returns the ERC20 LP token used by the contract.
    /// @return _token The ERC20 token used by the contract.
    function token() public pure returns (ERC20 _token) {
        return ERC20(_getArgAddress(0));
    }

    /// @notice Returns the strategy used by the contract.
    /// @return _strategy The strategy used by the contract.
    function strategy() public pure returns (IStrategy _strategy) {
        return IStrategy(_getArgAddress(20));
    }

    /// @notice Returns the liquidity gauge used by the contract.
    /// @return _liquidityGauge The liquidity gauge used by the contract.
    function liquidityGauge() public pure returns (ISDLiquidityGauge _liquidityGauge) {
        return ISDLiquidityGauge(_getArgAddress(40));
    }

    /// @notice Initializes the contract by setting allowances for the token and liquidity gauge.
    /// @dev Reverts if the contract has already been initialized.
    function initialize() external {
        if (token().allowance(address(this), address(strategy())) != 0) revert ALREADY_INITIALIZED();

        SafeTransferLib.safeApproveWithRetry(address(token()), address(strategy()), type(uint256).max);
        SafeTransferLib.safeApproveWithRetry(address(this), address(liquidityGauge()), type(uint256).max);
    }

    /// @notice Deposits a specified amount of LP tokens into the contract.
    /// @param _receiver The address for which the deposit is made.
    /// @param _amount The amount of tokens to be deposited.
    /// @param _doEarn If true, deposits LP tokens directly into the strategy.
    /// @dev If _doEarn is false, a fee is taken from the deposit to incentivize the next call to `earn`.
    /// @dev If _doEarn is true, the incentive token amount (if any) is added to the total amount, the incentive token amount is reset, and the total is deposited into the strategy.
    function deposit(address _receiver, uint256 _amount, bool _doEarn) public {
        SafeTransferLib.safeTransferFrom(address(token()), msg.sender, address(this), _amount);

        if (!_doEarn) {
            /// If doEarn is false, take a fee from the deposit to incentivize next call to earn.
            uint256 _incentiveTokenAmount = _amount.mulDiv(EARN_INCENTIVE_FEE, DENOMINATOR);

            /// Subtract incentive token amount from the total amount.
            _amount -= _incentiveTokenAmount;

            /// Add incentive token amount to the total incentive token amount.
            incentiveTokenAmount += _incentiveTokenAmount;
        } else {
            /// Add incentive token amount to the total amount.
            _amount += incentiveTokenAmount;

            /// Reset incentive token amount.
            incentiveTokenAmount = 0;

            _earn();
        }

        /// Mint amount equivalent to the amount deposited.
        _mint(address(this), _amount);

        /// Deposit for the receiver in the reward distributor gauge.
        liquidityGauge().deposit(_amount, _receiver);
    }

    /// @notice Withdraws a specified amount of LP tokens from the contract.
    /// @param _shares The amount of shares to be withdrawn.
    function withdraw(uint256 _shares) public {
        uint256 _balanceOfAccount = liquidityGauge().balanceOf(msg.sender);
        /// Revert if the sender does not have enough shares.
        if (_shares > _balanceOfAccount) revert NOT_ENOUGH_TOKENS();

        ///  Withdraw from the reward distributor gauge.
        liquidityGauge().withdraw(_shares, msg.sender, true);

        /// Burn vault shares.
        _burn(address(this), _shares);

        ///  Subtract the incentive token amount from the total amount or the next earn will dilute the shares.
        uint256 _tokenBalance = token().balanceOf(address(this)) - incentiveTokenAmount;

        /// Withdraw from the strategy if no enough tokens in the contract.
        if (_shares > _tokenBalance) {
            uint256 _toWithdraw = _shares - _tokenBalance;

            strategy().withdraw(address(token()), _toWithdraw);
        }

        /// Transfer the tokens to the sender.
        SafeTransferLib.safeTransfer(address(token()), msg.sender, _shares);
    }

    /// @notice Deposit all the LP tokens in the contract into the strategy.
    function _earn() internal {
        uint256 _balance = token().balanceOf(address(this));
        strategy().deposit(address(token()), _balance);
    }

    /// @notice Returns the name of the contract. (ERC20)
    function name() public view override returns (string memory) {
        return string(abi.encodePacked("sd", token().symbol(), " Vault"));
    }

    /// @notice Returns the symbol of the contract. (ERC20)
    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked("sd", token().symbol(), "-vault"));
    }

    /// @notice Returns the decimals of the contract. (ERC20)
    function decimals() public view override returns (uint8) {
        return token().decimals();
    }
}
