// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILiquidityGaugeV4 {
    /// @notice Reward token data structure
    struct Reward {
        address token;
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 last_update;
        uint256 integral;
    }

    /// @notice Emitted when tokens are deposited
    event Deposit(address indexed provider, uint256 value);
    /// @notice Emitted when tokens are withdrawn
    event Withdraw(address indexed provider, uint256 value);
    /// @notice Emitted when liquidity limit is updated
    event UpdateLiquidityLimit(
        address user, uint256 original_balance, uint256 original_supply, uint256 working_balance, uint256 working_supply
    );
    /// @notice Emitted when admin ownership is committed
    event CommitOwnership(address admin);
    /// @notice Emitted when admin ownership is applied
    event ApplyOwnership(address admin);
    /// @notice ERC20 Transfer event
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    /// @notice ERC20 Approval event
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    /// @notice Emitted when reward data is updated
    event RewardDataUpdate(address indexed _token, uint256 _amount);

    /// @notice SDT token address
    function SDT() external view returns (address);
    /// @notice Voting escrow contract address
    function voting_escrow() external view returns (address);
    /// @notice VeBoost proxy contract address
    function veBoost_proxy() external view returns (address);
    /// @notice The staking token address
    function staking_token() external view returns (address);
    /// @notice The number of decimals of the staking token
    function decimal_staking_token() external view returns (uint256);
    /// @notice Get user balance
    function balanceOf(address user) external view returns (uint256);
    /// @notice Total supply of staked tokens
    function totalSupply() external view returns (uint256);
    /// @notice ERC20 allowance
    function allowance(address owner, address spender) external view returns (uint256);
    /// @notice Token name
    function name() external view returns (string memory);
    /// @notice Token symbol
    function symbol() external view returns (string memory);
    /// @notice Get working balance for a user
    function working_balances(address user) external view returns (uint256);
    /// @notice Get total working supply
    function working_supply() external view returns (uint256);
    /// @notice Get the checkpoint of a user
    function integrate_checkpoint_of(address user) external view returns (uint256);
    /// @notice Number of reward tokens
    function reward_count() external view returns (uint256);
    /// @notice Array of reward token addresses
    function reward_tokens(uint256 index) external view returns (address);
    /// @notice Get reward data for a token
    function reward_data(address token) external view returns (Reward memory);
    /// @notice Get reward receiver for an address
    function rewards_receiver(address user) external view returns (address);
    /// @notice Current admin address
    function admin() external view returns (address);
    /// @notice Future admin address
    function future_admin() external view returns (address);
    /// @notice Claimer address
    function claimer() external view returns (address);
    /// @notice Whether the contract is initialized
    function initialized() external view returns (bool);

    /// @notice Get the number of decimals for this token
    function decimals() external view returns (uint256);
    /// @notice Record a checkpoint for an address
    function user_checkpoint(address addr) external returns (bool);
    /// @notice Get the number of already-claimed reward tokens for a user
    function claimed_reward(address _addr, address _token) external view returns (uint256);
    /// @notice Get the number of claimable reward tokens for a user
    function claimable_reward(address _user, address _reward_token) external view returns (uint256);
    /// @notice Set the default reward receiver for the caller
    function set_rewards_receiver(address _receiver) external;
    /// @notice Claim available reward tokens
    function claim_rewards(address _addr, address _receiver) external;
    /// @notice Claim available reward tokens for another address
    function claim_rewards_for(address _addr, address _receiver) external;
    /// @notice Kick an address for abusing their boost
    function kick(address addr) external;
    /// @notice Deposit LP tokens
    function deposit(uint256 _value, address _addr, bool _claim_rewards) external;
    /// @notice Withdraw LP tokens
    function withdraw(uint256 _value, bool _claim_rewards) external;
    /// @notice Transfer token for a specified address
    function transfer(address _to, uint256 _value) external returns (bool);
    /// @notice Transfer tokens from one address to another
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    /// @notice Approve the passed address to transfer tokens
    function approve(address _spender, uint256 _value) external returns (bool);
    /// @notice Increase the allowance granted to spender
    function increaseAllowance(address _spender, uint256 _added_value) external returns (bool);
    /// @notice Decrease the allowance granted to spender
    function decreaseAllowance(address _spender, uint256 _subtracted_value) external returns (bool);
    /// @notice Add a new reward token
    function add_reward(address _reward_token, address _distributor) external;
    /// @notice Set the reward distributor for a token
    function set_reward_distributor(address _reward_token, address _distributor) external;
    /// @notice Set the claimer address
    function set_claimer(address _claimer) external;
    /// @notice Deposit reward tokens
    function deposit_reward_token(address _reward_token, uint256 _amount) external;
    /// @notice Commit transfer of ownership
    function commit_transfer_ownership(address addr) external;
    /// @notice Accept transfer of ownership
    function accept_transfer_ownership() external;
    /// @notice Initialize the contract
    function initialize(
        address _staking_token,
        address _admin,
        address _SDT,
        address _voting_escrow,
        address _veBoost_proxy,
        address _distributor
    ) external;
}
