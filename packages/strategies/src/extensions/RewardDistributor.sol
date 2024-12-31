/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Super packed reward data structure into 2 slots
    /// Slot 1 [rewardsDistributor (160 bits) | rewardsDuration (32 bits) | lastUpdateTime (32 bits) | periodFinish (32 bits)]
    /// Slot 2 [rewardRate (96 bits) | rewardPerTokenStored (160 bits)]
    struct PackedReward {
        uint256 slot1; // [address(160) | duration(32) | lastUpdate(32) | finish(32)]
        uint256 slot2; // [rate(96) | rewardPerToken(160)]
    }

    /// @notice The asset being tracked by the reward distributor.
    IERC20 public immutable ASSET;

    mapping(address => PackedReward) public rewardData;

    /// @notice Active Reward Tokens.
    address[] public rewardTokens;

    /// @notice Combined user data mapping
    /// [rewardPerTokenPaid (160 bits) | claimable (48 bits) | claimed (48 bits)]
    mapping(address => mapping(address => uint256)) public userData;

    error UnauthorizedRewardsDistributor();
    error RewardAlreadyExists();
    error RewardRateOverflow();

    constructor(address asset) {
        ASSET = IERC20(asset);
    }

    function getRewardsDistributor(address token) public view returns (address) {
        return address(uint160(rewardData[token].slot1));
    }

    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32(rewardData[token].slot1 >> 160);
    }

    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32(rewardData[token].slot1 >> 192);
    }

    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32(rewardData[token].slot1 >> 224);
    }

    function getRewardRate(address token) public view returns (uint96) {
        return uint96(rewardData[token].slot2 >> 160);
    }

    function getRewardPerTokenStored(address token) public view returns (uint160) {
        return uint160(rewardData[token].slot2);
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        uint256 totalSupply = ASSET.totalSupply();
        if (totalSupply == 0) {
            return getRewardPerTokenStored(_rewardsToken);
        }
        return getRewardPerTokenStored(_rewardsToken) + (
            (lastTimeRewardApplicable(_rewardsToken) - getLastUpdateTime(_rewardsToken))
                * getRewardRate(_rewardsToken) * 1e18 / totalSupply
        );
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint256 userDataValue = userData[account][_rewardsToken];
        uint256 rewardPerTokenPaid = userDataValue >> 96;
        uint256 claimable = (userDataValue >> 48) & ((1 << 48) - 1);
        
        uint256 newEarned = ASSET.balanceOf(account) *
            (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
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

        // Pack slot1 data
        uint256 slot1 = uint256(uint160(getRewardsDistributor(_rewardsToken))) |
            (uint256(rewardsDuration) << 160) |
            (uint256(currentTime) << 192) |
            (uint256(currentTime + rewardsDuration) << 224);

        // Pack slot2 data
        uint256 slot2 = uint256(uint160(getRewardPerTokenStored(_rewardsToken))) |
            (uint256(uint96(newRewardRate)) << 160);

        rewardData[_rewardsToken].slot1 = slot1;
        rewardData[_rewardsToken].slot2 = slot2;
    }

    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = rewardPerToken(token);
            uint32 currentTime = uint32(block.timestamp);

            // Update slot1 (only lastUpdateTime)
            rewardData[token].slot1 = (rewardData[token].slot1 & ~(uint256(type(uint32).max) << 192)) |
                (uint256(currentTime) << 192);

            // Update slot2 (only rewardPerTokenStored)
            rewardData[token].slot2 = (rewardData[token].slot2 & (uint256(type(uint96).max) << 160)) |
                uint160(newRewardPerToken);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                // Pack user data: [rewardPerTokenPaid (160) | claimable (48) | claimed (48)]
                userData[account][token] = (uint256(uint160(newRewardPerToken)) << 96) |
                    (uint256(uint48(earnedAmount)) << 48) |
                    (userData[account][token] & ((1 << 48) - 1));
            }
        }
    }
}