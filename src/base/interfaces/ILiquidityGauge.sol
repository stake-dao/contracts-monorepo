// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

interface ILiquidityGauge {
    struct Reward {
        address token;
        address distributor;
        // solhint-disable-next-line
        uint256 period_finish;
        uint256 rate;
        // solhint-disable-next-line
        uint256 last_update;
        uint256 integral;
    }

    // solhint-disable-next-line
    function deposit_reward_token(address _rewardToken, uint256 _amount) external;

    // solhint-disable-next-line
    function claim_rewards_for(address _user, address _recipient) external;

    // solhint-disable-next-line
    function working_balances(address _address) external view returns (uint256);

    // solhint-disable-next-line
    function deposit(uint256 _value, address _addr) external;

    // solhint-disable-next-line
    function reward_tokens(uint256 _i) external view returns (address);

    // solhint-disable-next-line
    function reward_data(address _tokenReward) external view returns (Reward memory);

    function balanceOf(address) external returns (uint256);

    // solhint-disable-next-line
    function claimable_reward(address _user, address _reward_token) external view returns (uint256);

    // solhint-disable-next-line
    function claimable_tokens(address _user) external returns (uint256);

    // solhint-disable-next-line
    function user_checkpoint(address _user) external returns (bool);

    // solhint-disable-next-line
    function commit_transfer_ownership(address) external;

    // solhint-disable-next-line
    function claim_rewards() external;

    // solhint-disable-next-line
    function claim_rewards(address) external;

    // solhint-disable-next-line
    function claim_rewards(address, address) external;

    // solhint-disable-next-line
    function add_reward(address, address) external;

    // solhint-disable-next-line
    function set_claimer(address) external;

    function admin() external view returns (address);

    function future_admin() external view returns (address);

    // solhint-disable-next-line
    function set_reward_distributor(address _rewardToken, address _newDistrib) external;

    function initialize(
        // solhint-disable-next-line
        address staking_token,
        address admin,
        address sdt,
        // solhint-disable-next-line
        address voting_escrow,
        // solhint-disable-next-line
        address veBoost_proxy,
        address distributor
    ) external;

    function totalSupply() external returns (uint256);

    function withdraw(uint256 _value, bool _claimReward) external;

    // solhint-disable-next-line
    function accept_transfer_ownership() external;

    // solhint-disable-next-line
    function claimed_reward(address _addr, address _token) external view returns (uint256);

    // solhint-disable-next-line
    function set_rewards_receiver(address _receiver) external;
}
