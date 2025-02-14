/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/CoreVault.sol";
import "src/libraries/StorageMasks.sol";

/// @title RewardVault - Reward Distribution Vault
/// @notice ERC4626-compatible vault with reward distribution functionality
/// @dev Extends CoreVault with reward distribution capabilities:
///      - Efficient reward data storage using bit packing
///      - Multiple reward token support
///      - Reward rate and duration management
///      - User reward tracking and distribution
contract RewardVault is CoreVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Packed reward data structure into 2 slots for gas optimization
    /// @dev Slot 1: [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    /// @dev Slot 2: [rewardRate (96) | rewardPerTokenStored (160)]
    struct PackedReward {
        uint256 slot1;
        uint256 slot2;
    }

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice Mapping of reward token to its packed reward data
    mapping(address => PackedReward) private rewardData;

    /// @notice List of active reward tokens
    address[] public rewardTokens;

    /// @notice User reward data mapping
    /// @dev [rewardPerTokenPaid (160) | claimable (48) | claimed (48)]
    mapping(address => mapping(address => uint256)) private userData;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when an unauthorized address attempts to distribute rewards
    error UnauthorizedRewardsDistributor();

    /// @notice Error thrown when attempting to add a reward token that already exists
    error RewardAlreadyExists();

    /// @notice Error thrown when the calculated reward rate exceeds the maximum value
    error RewardRateOverflow();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor() CoreVault() {}

    //////////////////////////////////////////////////////
    /// --- REWARD DATA VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the rewards distributor for a given token
    /// @param token The reward token address
    /// @return The address of the rewards distributor
    function getRewardsDistributor(address token) public view returns (address) {
        return address(uint160(rewardData[token].slot1 & StorageMasks.REWARD_DISTRIBUTOR_MASK));
    }

    /// @notice Returns the rewards duration for a given token
    /// @param token The reward token address
    /// @return The duration in seconds
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & StorageMasks.REWARD_DURATION_MASK) >> 160);
    }

    /// @notice Returns the last update time for a given token
    /// @param token The reward token address
    /// @return The timestamp of the last update
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & StorageMasks.REWARD_LAST_UPDATE_MASK) >> 192);
    }

    /// @notice Returns the period finish time for a given token
    /// @param token The reward token address
    /// @return The timestamp when rewards end
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & StorageMasks.REWARD_PERIOD_FINISH_MASK) >> 224);
    }

    /// @notice Returns the reward rate for a given token
    /// @param token The reward token address
    /// @return The rewards per second rate
    function getRewardRate(address token) public view returns (uint96) {
        return uint96((rewardData[token].slot2 & StorageMasks.REWARD_RATE_MASK) >> 160);
    }

    /// @notice Returns the reward per token stored for a given token
    /// @param token The reward token address
    /// @return The accumulated rewards per token
    function getRewardPerTokenStored(address token) public view returns (uint160) {
        return uint160(rewardData[token].slot2 & StorageMasks.REWARD_PER_TOKEN_STORED_MASK);
    }

    //////////////////////////////////////////////////////
    /// --- REWARD CALCULATION FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the last applicable time for reward calculation
    /// @param _rewardsToken The reward token to check
    /// @return The minimum of current time and period finish
    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

    /// @notice Calculates the current reward per token
    /// @param _rewardsToken The reward token to calculate for
    /// @return The current reward per token rate
    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return getRewardPerTokenStored(_rewardsToken);
        }
        return getRewardPerTokenStored(_rewardsToken)
            + (
                (lastTimeRewardApplicable(_rewardsToken) - getLastUpdateTime(_rewardsToken)) * getRewardRate(_rewardsToken)
                    * 1e18 / totalSupply
            );
    }

    /// @notice Calculates the earned rewards for an account
    /// @param account The account to calculate earnings for
    /// @param _rewardsToken The reward token to calculate
    /// @return The total earned rewards
    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint256 userDataValue = userData[account][_rewardsToken];
        uint256 rewardPerTokenPaid = userDataValue & StorageMasks.USER_REWARD_PER_TOKEN_MASK;
        uint256 claimable = (userDataValue & StorageMasks.USER_CLAIMABLE_MASK) >> 160;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    /// @notice Returns the reward amount for the current duration
    /// @param _rewardsToken The reward token to check
    /// @return The total rewards for the duration
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
    }

    //////////////////////////////////////////////////////
    /// --- REWARD DISTRIBUTION FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Notifies the contract of new reward amount
    /// @param _rewardsToken The reward token being distributed
    /// @param reward The amount of rewards to distribute
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external {
        _updateReward(address(0));

        require(getRewardsDistributor(_rewardsToken) == msg.sender, UnauthorizedRewardsDistributor());

        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);

        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = getPeriodFinish(_rewardsToken);
        uint32 rewardsDuration = getRewardsDuration(_rewardsToken);
        uint256 newRewardRate;

        if (currentTime >= periodFinish) {
            newRewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - currentTime;
            uint256 leftover = remaining * getRewardRate(_rewardsToken);
            newRewardRate = (reward + leftover) / rewardsDuration;
        }

        if (newRewardRate > type(uint96).max) revert RewardRateOverflow();

        uint256 slot1 = (rewardData[_rewardsToken].slot1 & StorageMasks.REWARD_DISTRIBUTOR_MASK)
            | ((uint256(rewardsDuration) << 160) & StorageMasks.REWARD_DURATION_MASK)
            | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE_MASK)
            | ((uint256(currentTime + rewardsDuration) << 224) & StorageMasks.REWARD_PERIOD_FINISH_MASK);

        uint256 slot2 = (getRewardPerTokenStored(_rewardsToken) & StorageMasks.REWARD_PER_TOKEN_STORED_MASK)
            | ((uint256(newRewardRate) << 160) & StorageMasks.REWARD_RATE_MASK);

        rewardData[_rewardsToken].slot1 = slot1;
        rewardData[_rewardsToken].slot2 = slot2;
    }

    /// @notice Updates reward state for an account
    /// @param account The account to update rewards for
    function updateReward(address account) external {
        _updateReward(account);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @dev Internal function to update reward state
    /// @param account The account to update rewards for
    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = rewardPerToken(token);
            uint32 currentTime = uint32(block.timestamp);

            rewardData[token].slot1 = (rewardData[token].slot1 & ~StorageMasks.REWARD_LAST_UPDATE_MASK)
                | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE_MASK);

            rewardData[token].slot2 = (rewardData[token].slot2 & StorageMasks.REWARD_RATE_MASK)
                | (uint160(newRewardPerToken) & StorageMasks.REWARD_PER_TOKEN_STORED_MASK);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                userData[account][token] = (
                    uint256(uint160(newRewardPerToken)) & StorageMasks.USER_REWARD_PER_TOKEN_MASK
                ) | ((uint256(uint48(earnedAmount)) << 160) & StorageMasks.USER_CLAIMABLE_MASK)
                    | (userData[account][token] & StorageMasks.USER_CLAIMED_MASK);
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- HOOKS
    //////////////////////////////////////////////////////

    /// @notice Hook called before deposits to update rewards
    /// @param account The account depositing assets
    /// @param receiver The account receiving shares
    function _beforeDeposit(address account, address receiver) internal override {
        _updateReward(account);
        if (account != receiver) {
            _updateReward(receiver);
        }
    }

    /// @notice Hook called before withdrawals to update rewards
    /// @param account The account withdrawing assets
    function _beforeWithdraw(address account) internal override {
        _updateReward(account);
    }
}
