/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/CoreVault.sol";

import "@solady/src/utils/LibClone.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardVault is CoreVault {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Super packed reward data structure into 2 slots
    /// Slot 1 [rewardsDistributor (160 bits) | rewardsDuration (32 bits) | lastUpdateTime (32 bits) | periodFinish (32 bits)]
    /// Slot 2 [rewardRate (96 bits) | rewardPerTokenStored (160 bits)]
    struct PackedReward {
        uint256 slot1; // [address(160) | duration(32) | lastUpdate(32) | finish(32)]
        uint256 slot2; // [rate(96) | rewardPerToken(160)]
    }

    /// @notice Constants for bit manipulation - Slot 1
    uint256 private constant DISTRIBUTOR_MASK = (1 << 160) - 1;
    uint256 private constant DURATION_MASK = ((1 << 32) - 1) << 160;
    uint256 private constant LAST_UPDATE_MASK = ((1 << 32) - 1) << 192;
    uint256 private constant PERIOD_FINISH_MASK = ((1 << 32) - 1) << 224;

    /// @notice Constants for bit manipulation - Slot 2
    uint256 private constant REWARD_PER_TOKEN_MASK = (1 << 160) - 1;
    uint256 private constant REWARD_RATE_MASK = ((1 << 96) - 1) << 160;

    /// @notice Constants for bit manipulation - User Data
    uint256 private constant USER_REWARD_PER_TOKEN_MASK = (1 << 160) - 1;
    uint256 private constant USER_CLAIMABLE_MASK = ((1 << 48) - 1) << 160;
    uint256 private constant USER_CLAIMED_MASK = ((1 << 48) - 1) << 208;

    mapping(address => PackedReward) private rewardData;

    /// @notice Active Reward Tokens.
    address[] public rewardTokens;

    /// @notice Combined user data mapping
    /// [rewardPerTokenPaid (160 bits) | claimable (48 bits) | claimed (48 bits)]
    mapping(address => mapping(address => uint256)) private userData;

    error UnauthorizedRewardsDistributor();
    error RewardAlreadyExists();
    error RewardRateOverflow();

    constructor(address asset, bool softCheckpoint) CoreVault(asset, softCheckpoint) {}

    function getRewardsDistributor(address token) public view returns (address) {
        return address(uint160(rewardData[token].slot1 & DISTRIBUTOR_MASK));
    }

    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & DURATION_MASK) >> 160);
    }

    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & LAST_UPDATE_MASK) >> 192);
    }

    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32((rewardData[token].slot1 & PERIOD_FINISH_MASK) >> 224);
    }

    function getRewardRate(address token) public view returns (uint96) {
        return uint96((rewardData[token].slot2 & REWARD_RATE_MASK) >> 160);
    }

    function getRewardPerTokenStored(address token) public view returns (uint160) {
        return uint160(rewardData[token].slot2 & REWARD_PER_TOKEN_MASK);
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

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

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint256 userDataValue = userData[account][_rewardsToken];
        uint256 rewardPerTokenPaid = userDataValue & USER_REWARD_PER_TOKEN_MASK;
        uint256 claimable = (userDataValue & USER_CLAIMABLE_MASK) >> 160;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
    }

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

        // Pack slot1 data using masks
        uint256 slot1 = (rewardData[_rewardsToken].slot1 & DISTRIBUTOR_MASK)
            | ((uint256(rewardsDuration) << 160) & DURATION_MASK) | ((uint256(currentTime) << 192) & LAST_UPDATE_MASK)
            | ((uint256(currentTime + rewardsDuration) << 224) & PERIOD_FINISH_MASK);

        // Pack slot2 data using masks
        uint256 slot2 = (getRewardPerTokenStored(_rewardsToken) & REWARD_PER_TOKEN_MASK)
            | ((uint256(newRewardRate) << 160) & REWARD_RATE_MASK);

        rewardData[_rewardsToken].slot1 = slot1;
        rewardData[_rewardsToken].slot2 = slot2;
    }

    function updateReward(address account) external {
        _updateReward(account);
    }

    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = rewardPerToken(token);
            uint32 currentTime = uint32(block.timestamp);

            // Update slot1 (only lastUpdateTime) using masks
            rewardData[token].slot1 =
                (rewardData[token].slot1 & ~LAST_UPDATE_MASK) | ((uint256(currentTime) << 192) & LAST_UPDATE_MASK);

            // Update slot2 (only rewardPerTokenStored) using masks
            rewardData[token].slot2 =
                (rewardData[token].slot2 & REWARD_RATE_MASK) | (uint160(newRewardPerToken) & REWARD_PER_TOKEN_MASK);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                // Pack user data using masks
                userData[account][token] = (uint256(uint160(newRewardPerToken)) & USER_REWARD_PER_TOKEN_MASK)
                    | ((uint256(uint48(earnedAmount)) << 160) & USER_CLAIMABLE_MASK)
                    | (userData[account][token] & USER_CLAIMED_MASK);
            }
        }
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (to == address(0)) revert TransferToZeroAddress();
        if (to == address(this)) revert TransferToVault();

        if (amount > 0) {
            /// @dev Update the reward distributor for the receiver.
            _updateReward(to);

            /// @dev Update the reward distributor for the sender.
            _updateReward(from);

            /// @dev Get the pending rewards.
            uint256 pendingRewards = STRATEGY().pendingRewards(asset());

            /// @dev Checkpoint the vault. The accountant will deal with minting and burning.
            ACCOUNTANT().checkpoint(asset(), from, to, amount, CHECKPOINT, pendingRewards);
        }

        emit Transfer(from, to, amount);
    }

    function _beforeDeposit(address caller, address receiver, uint256, uint256) internal override {
        /// @dev Update the reward distributor for the caller.
        _updateReward(caller);

        if (caller != receiver) {
            /// @dev Update the reward distributor for the receiver.
            _updateReward(receiver);
        }
    }

    function _beforeWithdraw(address caller, address, address owner, uint256, uint256) internal override {
        /// @dev Update the reward distributor for the caller.
        _updateReward(caller);

        if (caller != owner) {
            /// @dev Update the reward distributor for the owner.
            _updateReward(owner);
        }
    }
}
