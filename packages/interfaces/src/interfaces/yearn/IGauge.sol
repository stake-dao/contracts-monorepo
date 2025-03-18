// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IGauge {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BoostedBalanceUpdated(address account, uint256 amount);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event DurationUpdated(uint256 duration, uint256 rewardRate, uint256 periodFinish);
    event Initialize(address indexed asset, address indexed owner);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RecipientUpdated(address indexed account, address indexed recipient);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsAdded(
        uint256 currentRewards,
        uint256 lastUpdateTime,
        uint256 periodFinish,
        uint256 rewardRate,
        uint256 historicalRewards
    );
    event RewardsQueued(address indexed from, uint256 amount);
    event Sweep(address indexed token, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferredPenalty(address indexed account, uint256 transfered);
    event UpdatedRewards(
        address indexed account,
        uint256 rewardPerTokenStored,
        uint256 lastUpdateTime,
        uint256 rewards,
        uint256 userRewardPerTokenPaid
    );
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function approve(address spender, uint256 amount) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function deposit(uint256 _assets, address _receiver) external returns (uint256);
    function deposit(uint256 _assets) external returns (uint256);
    function deposit() external returns (uint256);
    function getReward() external returns (bool);
    function getReward(address _account) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(address _asset, address _owner) external;
    function kick(address[] calldata _accounts) external;
    function mint(uint256 _shares, address _receiver) external returns (uint256);
    function queueNewRewards(uint256 _amount) external returns (bool);
    function redeem(uint256 _assets, address _receiver, address _owner) external returns (uint256);
    function renounceOwnership() external;
    function setDuration(uint256 _newDuration) external;
    function setRecipient(address _recipient) external;
    function sweep(address _token) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
    function withdraw() external returns (uint256);
    function withdraw(bool _claim) external returns (uint256);
    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256);
    function withdraw(uint256 _assets, address _receiver, address _owner, bool _claim) external returns (uint256);
    function BOOSTING_FACTOR() external view returns (uint256);
    function BOOST_DENOMINATOR() external view returns (uint256);
    function PRECISION_FACTOR() external view returns (uint256);
    function REWARD_TOKEN() external view returns (address);
    function VEYFI() external view returns (address);
    function VE_YFI_POOL() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function boostedBalanceOf(address _account) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function currentRewards() external view returns (uint256);
    function decimals() external view returns (uint8);
    function duration() external view returns (uint256);
    function earned(address _account) external view returns (uint256);
    function historicalRewards() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address _owner) external view returns (uint256);
    function maxWithdraw(address _owner) external view returns (uint256);
    function name() external view returns (string memory);
    function nextBoostedBalanceOf(address _account) external view returns (uint256);
    function owner() external view returns (address);
    function periodFinish() external view returns (uint256);
    function previewDeposit(uint256 _assets) external view returns (uint256);
    function previewMint(uint256 _shares) external view returns (uint256);
    function previewRedeem(uint256 _assets) external view returns (uint256);
    function previewWithdraw(uint256 _assets) external view returns (uint256);
    function queuedRewards() external view returns (uint256);
    function recipients(address) external view returns (address);
    function rewardPerToken() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewards(address) external view returns (uint256);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function userRewardPerTokenPaid(address) external view returns (uint256);
}
