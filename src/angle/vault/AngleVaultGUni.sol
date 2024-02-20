//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "openzeppelin-contracts/utils/Address.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {AngleStrategy} from "src/angle/strategy/AngleStrategy.sol";

contract AngleVaultGUni is ERC20 {
    using SafeERC20 for ERC20;
    using Address for address;

    ERC20 public token;
    address public governance;
    uint256 public withdrawalFee;
    uint256 public keeperFee;
    address public liquidityGauge;
    uint256 public accumulatedFee;
    uint256 public scalingFactor;
    AngleStrategy public angleStrategy;
    uint256 public min;
    uint256 public constant max = 10_000;

    event Earn(address _token, uint256 _amount);
    event Deposit(address _depositor, uint256 _amount);
    event Withdraw(address _depositor, uint256 _amount);

    constructor(
        ERC20 _token,
        address _governance,
        string memory name_,
        string memory symbol_,
        AngleStrategy _angleStrategy,
        uint256 _scalingFactor
    ) ERC20(name_, symbol_) {
        token = _token;
        governance = _governance;
        min = 10_000;
        keeperFee = 10; // %0.1
        angleStrategy = _angleStrategy;
        scalingFactor = _scalingFactor;
    }

    function deposit(address _staker, uint256 _amount, bool _earn) public {
        require(address(liquidityGauge) != address(0), "Gauge not yet initialized");
        token.safeTransferFrom(msg.sender, address(this), _amount);
        if (!_earn) {
            uint256 keeperCut = (_amount * keeperFee) / 10_000;
            _amount -= keeperCut;
            accumulatedFee += keeperCut;
        } else {
            _amount += accumulatedFee;
            accumulatedFee = 0;
        }
        _mint(address(this), _amount);
        ERC20(address(this)).approve(liquidityGauge, _amount);
        ILiquidityGaugeStrat(liquidityGauge).deposit(_amount, _staker);
        if (_earn) {
            earn();
        }
        emit Deposit(_staker, _amount);
    }

    function withdraw(uint256 _shares) public {
        uint256 userTotalShares = ILiquidityGaugeStrat(liquidityGauge).balanceOf(msg.sender);
        require(_shares <= userTotalShares, "Not enough staked");
        ILiquidityGaugeStrat(liquidityGauge).withdraw(_shares, msg.sender, true);
        _burn(address(this), _shares);
        uint256 tokenBalance = token.balanceOf(address(this)) - accumulatedFee;

        if (_shares > tokenBalance) {
            uint256 amountToWithdraw = ((_shares - tokenBalance) * scalingFactor) / 1e18;
            angleStrategy.withdraw(address(token), amountToWithdraw);
            uint256 scaledUpAmountToWithdraw = (amountToWithdraw * 1e18) / scalingFactor;
            uint256 withdrawFee = (scaledUpAmountToWithdraw * withdrawalFee) / 10_000;
            token.safeTransfer(governance, withdrawFee);
            _shares = token.balanceOf(address(this)) - accumulatedFee;
        }

        token.safeTransfer(msg.sender, _shares);
        emit Withdraw(msg.sender, _shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setKeeperFee(uint256 _newFee) external {
        require(msg.sender == governance, "!governance");
        keeperFee = _newFee;
    }

    function setLiquidityGauge(address _liquidityGauge) external {
        require(msg.sender == governance, "!governance");
        liquidityGauge = _liquidityGauge;
    }

    function setAngleStrategy(AngleStrategy _newStrat) external {
        require(msg.sender == governance, "!governance");
        angleStrategy = _newStrat;
    }

    function decimals() public view override returns (uint8) {
        return token.decimals();
    }

    function setWithdrawnFee(uint256 _newFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _newFee;
    }

    function setMin(uint256 _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    function setScalingFactor(uint256 _newScalingFactor) external {
        require(msg.sender == governance, "!governance");
        scalingFactor = _newScalingFactor;
    }

    function available() public view returns (uint256) {
        return ((token.balanceOf(address(this)) - accumulatedFee) * min) / max;
    }

    function earn() internal {
        uint256 tokenBalance = available();
        token.approve(address(angleStrategy), 0);
        token.approve(address(angleStrategy), tokenBalance);
        angleStrategy.deposit(address(token), tokenBalance);
        emit Earn(address(token), tokenBalance);
    }
}
