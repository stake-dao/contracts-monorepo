/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@solady/src/utils/LibClone.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/CoreVault.sol";

/// @title RewardVault
/// @notice Extension of CoreVault that adds reward distribution functionality
/// @dev Uses bit packing to optimize storage of reward data
contract RewardVault is CoreVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Packed reward data structure into 2 slots for gas optimization
    /// @dev Slot 1: [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    /// @dev Slot 2: [rewardRate (96) | rewardPerTokenStored (160)]
    struct PackedReward {
        uint256 slot1;
        uint256 slot2;
    }

    /// @dev Bit masks for slot 1
    uint256 private constant DISTRIBUTOR_MASK = (1 << 160) - 1;
    uint256 private constant DURATION_MASK = ((1 << 32) - 1) << 160;
    uint256 private constant LAST_UPDATE_MASK = ((1 << 32) - 1) << 192;
    uint256 private constant PERIOD_FINISH_MASK = ((1 << 32) - 1) << 224;

    /// @dev Bit masks for slot 2
    uint256 private constant REWARD_PER_TOKEN_MASK = (1 << 160) - 1;
    uint256 private constant REWARD_RATE_MASK = ((1 << 96) - 1) << 160;

    /// @dev Bit masks for user data
    uint256 private constant USER_REWARD_PER_TOKEN_MASK = (1 << 160) - 1;
    uint256 private constant USER_CLAIMABLE_MASK = ((1 << 48) - 1) << 160;
    uint256 private constant USER_CLAIMED_MASK = ((1 << 48) - 1) << 208;

    /// @notice Mapping of reward token to its packed reward data
    mapping(address => PackedReward) private rewardData;

    /// @notice List of active reward tokens
    address[] public rewardTokens;

    /// @notice User reward data mapping
    /// @dev [rewardPerTokenPaid (160) | claimable (48) | claimed (48)]
    mapping(address => mapping(address => uint256)) private userData;

    error UnauthorizedRewardsDistributor();
    error RewardAlreadyExists();
    error RewardRateOverflow();

    /// @notice Gets the rewards distributor for a token
    /// @param token The reward token address
    /// @return The distributor address
    function getRewardsDistributor(address token) public view returns (address) {
        return address(uint160(rewardData[token].slot1 & DISTRIBUTOR_MASK));
    }

    /// @notice Gets the rewards duration for a token
    /// @param token The reward token address
    /// @return The duration in seconds
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & DURATION_MASK) >> 160);
    }

    /// @notice Gets the last update time for a token
    /// @param token The reward token address
    /// @return The last update timestamp
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & LAST_UPDATE_MASK) >> 192);
    }

    /// @notice Gets the period finish time for a token
    /// @param token The reward token address
    /// @return The period finish timestamp
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & PERIOD_FINISH_MASK) >> 224);
    }

    /// @notice Gets the reward rate for a token
    /// @param token The reward token address
    /// @return The reward rate per second
    function getRewardRate(address token) public view returns (uint96) {
        return uint96((rewardData[token].slot2 & REWARD_RATE_MASK) >> 160);
    }

    /// @notice Gets the stored reward per token
    /// @param token The reward token address
    /// @return The stored reward per token value
    function getRewardPerTokenStored(address token) public view returns (uint160) {
        return uint160(rewardData[token].slot2 & REWARD_PER_TOKEN_MASK);
    }

    /// @notice Gets the last applicable time for reward calculation
    /// @param _rewardsToken The reward token address
    /// @return The last applicable timestamp
    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

    /// @notice Calculates the current reward per token
    /// @param _rewardsToken The reward token address
    /// @return The current reward per token value
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

    /// @notice Calculates earned rewards for an account
    /// @param account The account to check
    /// @param _rewardsToken The reward token address
    /// @return The amount of rewards earned
    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint256 userDataValue = userData[account][_rewardsToken];
        uint256 rewardPerTokenPaid = userDataValue & USER_REWARD_PER_TOKEN_MASK;
        uint256 claimable = (userDataValue & USER_CLAIMABLE_MASK) >> 160;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    /// @notice Gets the reward amount for the current duration
    /// @param _rewardsToken The reward token address
    /// @return The total reward amount for the duration
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
    }

    /// @notice Notifies the contract of a reward amount
    /// @param _rewardsToken The reward token address
    /// @param reward The amount of reward tokens
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external {
        _updateReward(address(0));

        if (getRewardsDistributor(_rewardsToken) != msg.sender) revert UnauthorizedRewardsDistributor();
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

        uint256 slot1 = (rewardData[_rewardsToken].slot1 & DISTRIBUTOR_MASK)
            | ((uint256(rewardsDuration) << 160) & DURATION_MASK) | ((uint256(currentTime) << 192) & LAST_UPDATE_MASK)
            | ((uint256(currentTime + rewardsDuration) << 224) & PERIOD_FINISH_MASK);

        uint256 slot2 = (getRewardPerTokenStored(_rewardsToken) & REWARD_PER_TOKEN_MASK)
            | ((uint256(newRewardRate) << 160) & REWARD_RATE_MASK);

        rewardData[_rewardsToken].slot1 = slot1;
        rewardData[_rewardsToken].slot2 = slot2;
    }

    /// @notice Updates reward state for an account
    /// @param account The account to update rewards for
    function updateReward(address account) external {
        _updateReward(account);
    }

    /// @dev Internal function to update reward state
    /// @param account The account to update rewards for
    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = rewardPerToken(token);
            uint32 currentTime = uint32(block.timestamp);

            rewardData[token].slot1 =
                (rewardData[token].slot1 & ~LAST_UPDATE_MASK) | ((uint256(currentTime) << 192) & LAST_UPDATE_MASK);

            rewardData[token].slot2 =
                (rewardData[token].slot2 & REWARD_RATE_MASK) | (uint160(newRewardPerToken) & REWARD_PER_TOKEN_MASK);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                userData[account][token] = (uint256(uint160(newRewardPerToken)) & USER_REWARD_PER_TOKEN_MASK)
                    | ((uint256(uint48(earnedAmount)) << 160) & USER_CLAIMABLE_MASK)
                    | (userData[account][token] & USER_CLAIMED_MASK);
            }
        }
    }

    /// @inheritdoc ERC20
    function _transfer(address from, address to, uint256 amount) internal override {
        if (to == address(0)) revert TransferToZeroAddress();
        if (to == address(this)) revert TransferToVault();

        if (amount > 0) {
            _updateReward(to);
            _updateReward(from);

            uint256 pendingRewards = STRATEGY().pendingRewards(asset());
            ACCOUNTANT().checkpoint(asset(), from, to, amount, pendingRewards);
        }

        emit Transfer(from, to, amount);
    }

    /// @dev Hook that is called before any deposit.
    function _beforeDeposit(address caller, address receiver, uint256, uint256) internal override {
        _updateReward(caller);

        if (caller != receiver) {
            _updateReward(receiver);
        }
    }

    /// @dev Hook that is called before any withdrawal.
    function _beforeWithdraw(address caller, address receiver, address, uint256, uint256) internal override {
        _updateReward(caller);

        if (caller != receiver) {
            _updateReward(receiver);
        }
    }
}
