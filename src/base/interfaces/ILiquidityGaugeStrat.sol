// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILiquidityGaugeStrat {
    struct Reward {
        address token;
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 last_update;
        uint256 integral;
    }

    function asset() external view returns (address);

    function earned(address) external view returns (uint256);

    function getReward(address) external;

    // solhint-disable-next-line
    function add_reward(address _token, address _distributor) external;

    function balanceOf(address _user) external view returns (uint256);

    // solhint-disable-next-line
    function commit_transfer_ownership(address _owner) external;

    // solhint-disable-next-line
    function claim_rewards(address _user) external;

    function deposit(uint256 _value, address _user) external;

    // solhint-disable-next-line
    function deposit_reward_token(address _rewardToken, uint256 _amount) external;

    function initialize(
        address _stakingToken,
        address _admin,
        address _token,
        address _veToken,
        address _veBoost,
        address _sdtDistributor,
        address _vault,
        string memory _symbol
    ) external;

    // solhint-disable-next-line
    function lp_token() external view returns (address);

    // solhint-disable-next-line
    function reward_tokens(uint256 _i) external view returns (address);

    // solhint-disable-next-line
    function set_claimer(address _claimReward) external;

    // solhint-disable-next-line
    function set_vault(address _vault) external;

    function totalSupply() external returns (uint256);

    function withdraw(uint256 _value, address _user, bool _claim) external;

    function withdraw(uint256 _value, address _user) external;

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function transfer(address _to, uint256 amount) external;

    function claimable_reward(address _user, address _token) external view returns (uint256);

    function reward_data(address _token) external view returns (Reward memory);

    function working_balances(address _address) external returns (uint256);

    function admin() external returns (address);

    function set_reward_distributor(address _rewardToken, address _newDistrib) external;
}
