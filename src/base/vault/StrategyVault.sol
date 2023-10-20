//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "src/base/interfaces/ILiquidityGaugeStrat.sol";
import "src/base/interfaces/IStrategy.sol";

contract StrategyVault is ERC20Upgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    using AddressUpgradeable for address;

    error GAUGE_NOT_SET();
    error GOVERNANCE();
    error FUTURE_GOVERNANCE();
    error NOT_ENOUGH_STAKED();

    address public locker;
    ERC20Upgradeable public token;
    address public governance;
    address public futureGovernance;
    ILiquidityGaugeStrat public liquidityGauge;
    IStrategy public strategy;

    event Deposit(address _staker, uint256 _amount);
    event GovernanceChanged(address _gov);
    event LiquidityGaugeChanged(address _lg);
    event StrategySet(address _strategy);
    event Withdraw(address _staker, uint256 _amount);

    function init(
        address _token,
        address _governance,
        string memory name_,
        string memory symbol_,
        address _strategy,
        address _locker
    ) public initializer {
        __ERC20_init(name_, symbol_);
        token = ERC20Upgradeable(_token);
        governance = _governance;
        strategy = IStrategy(_strategy);
        locker = _locker;
    }

    /// @notice function to deposit lp tokens
    /// @param _staker address to deposit for
    /// @param _amount amount to deposit
    function deposit(address _staker, uint256 _amount) external {
        if (address(liquidityGauge) == address(0)) revert GAUGE_NOT_SET();
        // transfer LPT to the locker to be hold
        token.safeTransferFrom(msg.sender, locker, _amount);
        // mint the same amount of sd LP and stake it to the gauge
        _mint(address(this), _amount);
        liquidityGauge.deposit(_amount, _staker);
        emit Deposit(_staker, _amount);
    }

    /// @notice function to withdraw lp tokens
    /// @param _amount amount to withdraw
    function withdraw(uint256 _amount) public {
        uint256 userAmount = liquidityGauge.balanceOf(msg.sender);
        if (_amount > userAmount) revert NOT_ENOUGH_STAKED();
        // withdraw the token and collect rewards
        liquidityGauge.withdraw(_amount, msg.sender, true);
        _burn(address(this), _amount);
        strategy.withdraw(address(token), _amount, msg.sender);
        emit Withdraw(msg.sender, _amount);
    }

    /// @notice function to withdraw all user's lp tokens deposited
    function withdrawAll() external {
        withdraw(liquidityGauge.balanceOf(msg.sender));
    }

    /// @notice function to set the liquidity gauge
    /// @param _liquidityGauge gauge address
    function setLiquidityGauge(address _liquidityGauge) external {
        if (msg.sender != governance) revert GOVERNANCE();
        // it will do an infinite approve to deposit token from here
        ERC20Upgradeable(address(this)).approve(_liquidityGauge, type(uint256).max);
        emit LiquidityGaugeChanged(address(liquidityGauge = ILiquidityGaugeStrat(_liquidityGauge)));
    }

    /// @notice function to set the strategy
    /// @param _strategy strategy address
    function setStrategy(address _strategy) external {
        if (msg.sender != governance) revert GOVERNANCE();
        emit StrategySet(address(strategy = IStrategy(_strategy)));
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external {
        if (msg.sender != governance) revert GOVERNANCE();
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert FUTURE_GOVERNANCE();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }

    /// @notice function to get the sdToken decimals
    function decimals() public view override returns (uint8) {
        return token.decimals();
    }
}
