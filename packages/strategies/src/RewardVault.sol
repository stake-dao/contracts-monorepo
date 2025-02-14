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
///      - Account reward tracking and distribution
contract RewardVault is CoreVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Packed reward data structure into 2 slots for gas optimization
    /// @dev Slot 1: [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    /// @dev Slot 2: [rewardRate (128) | rewardPerTokenStored (128)]
    struct PackedReward {
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        uint256 rewardRateAndRewardPerTokenStoredSlot;
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev [rewardPerTokenPaid (128) | claimable (128)]
    struct PackedAccount {
        uint256 rewardPerTokenPaidAndClaimableSlot;
    }

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice List of active reward tokens
    address[] public rewardTokens;

    /// @notice Mapping of reward token to its packed reward data
    mapping(address => PackedReward) private rewardData;

    /// @notice Account reward data mapping
    /// @dev [rewardPerTokenPaid (128) | claimable (128)]
    mapping(address => mapping(address => PackedAccount)) private accountData;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the calculated reward rate exceeds the maximum value
    error RewardRateOverflow();

    /// @notice Error thrown when attempting to add a reward token that already exists
    error RewardAlreadyExists();

    /// @notice Error thrown when an unauthorized address attempts to distribute rewards
    error UnauthorizedRewardsDistributor();

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
        return address(
            uint160(
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_DISTRIBUTOR
            )
        );
    }

    /// @notice Returns the rewards duration for a given token
    /// @param token The reward token address
    /// @return The duration in seconds
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_DURATION)
                >> 160
        );
    }

    /// @notice Returns the last update time for a given token
    /// @param token The reward token address
    /// @return The timestamp of the last update
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_LAST_UPDATE)
                >> 192
        );
    }

    /// @notice Returns the period finish time for a given token
    /// @param token The reward token address
    /// @return The timestamp when rewards end
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32(
            (
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_PERIOD_FINISH
            ) >> 224
        );
    }

    /// @notice Returns the reward rate for a given token
    /// @param token The reward token address
    /// @return The rewards per second rate
    function getRewardRate(address token) public view returns (uint128) {
        return uint128((rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_RATE) >> 128);
    }

    /// @notice Returns the reward per token stored for a given token
    /// @param token The reward token address
    /// @return The accumulated rewards per token
    function getRewardPerTokenStored(address token) public view returns (uint128) {
        return uint128(rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_PER_TOKEN_STORED);
    }

    /// @notice Returns the reward amount for the current duration
    /// @param _rewardsToken The reward token to check
    /// @return The total rewards for the duration
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
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
        PackedAccount storage accountDataValue = accountData[account][_rewardsToken];
        uint256 rewardPerTokenPaid =
            accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_REWARD_PER_TOKEN;
        uint256 claimable =
            (accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_CLAIMABLE) >> 128;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    //////////////////////////////////////////////////////
    /// --- REWARD DISTRIBUTION FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Updates reward state for an account
    /// @param account The account to update rewards for
    function updateReward(address account) external {
        _updateReward(account);
    }

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

        if (newRewardRate > type(uint128).max) revert RewardRateOverflow();

        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot = (
            rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                & StorageMasks.REWARD_DISTRIBUTOR
        ) | ((uint256(rewardsDuration) << 160) & StorageMasks.REWARD_DURATION)
            | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE)
            | ((uint256(currentTime + rewardsDuration) << 224) & StorageMasks.REWARD_PERIOD_FINISH);

        uint256 rewardRateAndRewardPerTokenStoredSlot = (
            getRewardPerTokenStored(_rewardsToken) & StorageMasks.REWARD_PER_TOKEN_STORED
        ) | ((uint256(newRewardRate) << 128) & StorageMasks.REWARD_RATE);

        rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot =
            distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        rewardData[_rewardsToken].rewardRateAndRewardPerTokenStoredSlot = rewardRateAndRewardPerTokenStoredSlot;
    }

    /// @dev Internal function to update reward state
    /// @param account The account to update rewards for
    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = rewardPerToken(token);
            uint32 currentTime = uint32(block.timestamp);

            rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot = (
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & ~StorageMasks.REWARD_LAST_UPDATE
            ) | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE);

            rewardData[token].rewardRateAndRewardPerTokenStoredSlot = (
                rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_RATE
            ) | (uint128(newRewardPerToken) & StorageMasks.REWARD_PER_TOKEN_STORED);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                PackedAccount storage accountDataValue = accountData[account][token];

                // Update account data with new reward per token and claimable amount
                accountDataValue.rewardPerTokenPaidAndClaimableSlot = (
                    uint128(newRewardPerToken) & StorageMasks.ACCOUNT_REWARD_PER_TOKEN
                ) | ((uint256(uint128(earnedAmount)) << 128) & StorageMasks.ACCOUNT_CLAIMABLE);
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
