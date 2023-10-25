//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IStrategy} from "src/base/interfaces/IStrategy.sol";
import {Clone} from "solady/utils/Clone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract StrategyVaultImpl is Clone, ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    error NOT_ENOUGH_STAKED();
    error ONLY_FACTORY();

    uint256 public accumulatedFee;

    event Deposit(address _staker, uint256 _amount);
    event Withdraw(address _staker, uint256 _amount);

    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert ONLY_FACTORY();
        _;
    }

    function init() external onlyFactory {
        SafeTransferLib.safeApproveWithRetry(address(this), address(liquidityGauge()), type(uint256).max);
    }

    /// @notice function to deposit lp tokens
    /// @param _staker address to deposit for
    /// @param _amount amount to deposit
    function deposit(address _staker, uint256 _amount, bool _earn) external {
        // transfer LP to the locker to be hold
        SafeTransferLib.safeTransferFrom(address(token()), msg.sender, address(this), _amount);
        if (!_earn) {
            uint256 keeperCut = (_amount * keeperFee()) / 10_000;
            _amount -= keeperCut;
            accumulatedFee += keeperCut;
        } else {
            _amount += accumulatedFee;
            accumulatedFee = 0;
        }
        // mint the same amount of sd LP and stake it to the gauge
        _mint(address(this), _amount);
        liquidityGauge().deposit(_amount, _staker);
        if (_earn) {
            earn();
        }
        emit Deposit(_staker, _amount);
    }

    /// @notice function to withdraw lp tokens
    /// @param _amount amount to withdraw
    function withdraw(uint256 _amount) public {
        uint256 userAmount = liquidityGauge().balanceOf(msg.sender);
        if (_amount > userAmount) revert NOT_ENOUGH_STAKED();
        // withdraw the token and collect rewards
        liquidityGauge().withdraw(_amount, msg.sender, true);
        _burn(address(this), _amount);
        uint256 tokenBalance = token().balanceOf(address(this)) - accumulatedFee;
        if (_amount > tokenBalance) {
            uint256 amountToWithdraw = _amount - tokenBalance;
            strategy().withdraw(address(token()), amountToWithdraw);
        }
        SafeTransferLib.safeTransfer(address(token()), msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /// @notice function to withdraw all user's lp tokens deposited
    function withdrawAll() external {
        withdraw(liquidityGauge().balanceOf(msg.sender));
    }

    function available() public view returns (uint256) {
        return (token().balanceOf(address(this)) - accumulatedFee);
    }

    /// @notice internal function to move funds to the strategy
    function earn() internal {
        uint256 tokenBalance = available();
        SafeTransferLib.safeApproveWithRetry(address(token()), address(strategy()), 0);
        SafeTransferLib.safeApproveWithRetry(address(token()), address(strategy()), tokenBalance);
        strategy().deposit(address(token()), tokenBalance);
        //emit Earn(address(token()), tokenBalance);
    }

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    function token() public pure returns(ERC20 _token) {
        return ERC20(_getArgAddress(0));
    }

    function factory() public pure returns(address _factory) {
        return _getArgAddress(20);
    }

    function strategy() public pure returns(IStrategy _strategy) {
        return IStrategy(_getArgAddress(40));
    }

    function locker() public pure returns(address _locker) {
        return _getArgAddress(60);
    }

    function liquidityGauge() public pure returns(ILiquidityGaugeStrat _lg) {
        return ILiquidityGaugeStrat(_getArgAddress(80));
    }

    function keeperFee() public pure returns(uint256 _keeperFee) {
        return _getArgUint256(100);
    }

    function name() public pure override returns(string memory) {
        string memory a = "a";
        return a;
    }

    function symbol() public pure override returns(string memory) {
        string memory b = "b";
        return b;
    }

    function decimals() public view override returns(uint8) {
        return token().decimals();
    }
}
