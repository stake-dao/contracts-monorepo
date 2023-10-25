// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {IStrategy} from "src/base/interfaces/IStrategy.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ISDLiquidityGauge} from "src/base/interfaces/ISDLiquidityGauge.sol";

/// @notice Vault implementation for Stake DAO.
/// @dev Deposit LP tokens to Stake DAO and receive sdGauge tokens as a receipt.
contract StrategyVaultImpl is ERC20, Clone {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Denominator for percentage calculations.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Small fee to incentivize next call to earn.
    uint256 public constant EARN_INCENTIVE_FEE = 10;

    /// @notice Total amount of incentive token.
    uint256 public incentiveTokenAmount;

    /// @notice Throws if the contract is already initialized.
    error ALREADY_INITIALIZED();

    /// @notice Throws if the sender does not have enough tokens.
    error NOT_ENOUGH_TOKENS();

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    function token() public pure returns (ERC20 _token) {
        return ERC20(_getArgAddress(0));
    }

    function strategy() public pure returns (IStrategy _strategy) {
        return IStrategy(_getArgAddress(20));
    }

    function liquidityGauge() public pure returns (ISDLiquidityGauge _liquidityGauge) {
        return ISDLiquidityGauge(_getArgAddress(40));
    }

    function initialize() external {
        if (token().allowance(address(this), address(strategy())) != 0) revert ALREADY_INITIALIZED();

        SafeTransferLib.safeApproveWithRetry(address(token()), address(strategy()), type(uint256).max);
        SafeTransferLib.safeApproveWithRetry(address(this), address(liquidityGauge()), type(uint256).max);
    }

    function deposit(address _receiver, uint256 _amount, bool _doEarn) public {
        SafeTransferLib.safeTransferFrom(address(token()), msg.sender, address(this), _amount);

        if (!_doEarn) {
            /// If doEarn is false, take a fee from the deposit to incentivize next call to earn.
            uint256 _incentiveTokenAmount = _amount.mulDivDown(EARN_INCENTIVE_FEE, DENOMINATOR);

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

    function withdraw(uint256 _shares) public {
        uint256 _balanceOfAccount = liquidityGauge().balanceOf(msg.sender);
        /// Revert if the sender does not have enough shares.
        if (_shares > _balanceOfAccount) revert NOT_ENOUGH_TOKENS();

        ///  Withdraw from the reward distributor gauge.
        liquidityGauge().withdraw(_shares, msg.sender, true);

        /// Burn vault shares.
        _burn(address(this), _shares);

        ///  Substract the incentive token amount from the total amount or the next earn will dilute the shares.
        uint256 _tokenBalance = token().balanceOf(address(this)) - incentiveTokenAmount;

        /// Withdraw from the strategy if no enough tokens in the contract.
        if (_shares > _tokenBalance) {
            uint256 _toWithdraw = _shares - _tokenBalance;

            strategy().withdraw(address(token()), _toWithdraw);
        }

        /// Transfer the tokens to the sender.
        SafeTransferLib.safeTransfer(address(token()), msg.sender, _shares);
    }

    function _earn() internal {
        uint256 _balance = token().balanceOf(address(this));
        strategy().deposit(address(token()), _balance);
    }

    function name() public view override returns (string memory) {
        return string(abi.encodePacked("sd", token().symbol(), " Vault"));
    }

    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked("sd", token().symbol(), "-vault"));
    }

    function decimals() public view override returns (uint8) {
        return token().decimals();
    }
}