// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IStrategy} from "src/base/interfaces/IStrategy.sol";

contract RewardReceiverSingleToken {
    error ZERO_AMOUNT();

    ILiquidityGaugeStrat public immutable sdGauge;
    IERC20 public immutable rewardToken;
    address public immutable strategy;

    event Notified(address indexed sdgauge, uint256 notified, uint256 feesCharged);

    constructor(address _rewardToken, address _sdGauge, address _strategy) {
        sdGauge = ILiquidityGaugeStrat(_sdGauge);
        strategy = _strategy;
        rewardToken = IERC20(_rewardToken);
        rewardToken.approve(_sdGauge, type(uint256).max);
    }

    /// @notice function to notify the whole reward
    function notifyReward() external {
        uint256 amount = IERC20(rewardToken).balanceOf(address(this));
        if (amount == 0) revert ZERO_AMOUNT();
        uint256 netReward = _chargeFee(amount);
        sdGauge.deposit_reward_token(address(rewardToken), netReward);
        emit Notified(address(sdGauge), netReward, amount - netReward);
    }

    /// @notice internal function to transfer protocolFee to the feeRecipient
    function _chargeFee(uint256 _amount) internal returns (uint256) {
        uint256 protocolFee = IStrategy(strategy).protocolFeesPercent();
        uint256 protocolPart = _amount * protocolFee / 10_000;
        address feeReceiver = IStrategy(strategy).feeReceiver();
        IERC20(rewardToken).transfer(feeReceiver, protocolPart);
        return _amount - protocolPart;
    }
}