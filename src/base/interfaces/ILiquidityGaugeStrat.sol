// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILiquidityGaugeStrat {
    // solhint-disable-next-line
    function add_reward(address _token, address _distributor) external;

    function balanceOf(address _user) external view returns (uint256);

    // solhint-disable-next-line
    function claim_rewards(address _user) external;

    function deposit(uint256 _value, address _user) external;

    // solhint-disable-next-line
    function deposit_reward_token(address _rewardToken, uint256 _amount) external;

    // solhint-disable-next-line
    function reward_tokens(uint256 _i) external view returns (address);

    function withdraw(uint256 _value, address _user, bool _claim) external;
}
