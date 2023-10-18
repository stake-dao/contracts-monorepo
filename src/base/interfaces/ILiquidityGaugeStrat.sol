// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILiquidityGaugeStrat {
    function deposit(uint256 _value, address _user) external;

    // solhint-disable-next-line
    function deposit_reward_token(address _rewardToken, uint256 _amount) external;

    function withdraw(uint256 _value, address _user, bool _claim) external;

    function balanceOf(address _user) external view returns (uint256);
}