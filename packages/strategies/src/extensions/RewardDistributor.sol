/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Packed reward data structure
    /// [0-159]   rewardRate (uint160)
    /// [160-191] rewardsDuration (uint32)
    /// [192-223] lastUpdateTime (uint32)
    /// [224-255] periodFinish (uint32)
    struct PackedReward {
        address rewardsDistributor;
        uint256 rewardPerTokenStored;
        uint256 packedData;
    }

    /// @notice The asset being tracked by the reward distributor.
    IERC20 public immutable ASSET;

    /// @notice Packed reward data per token
    mapping(address => PackedReward) public rewardData;

    /// @notice Active Reward Tokens.
    address[] public rewardTokens;

    /// @notice User reward data - packed [claimable amount (128 bits)][claimed amount (128 bits)]
    mapping(address => mapping(address => uint256)) public userRewardData;

    /// @notice User Reward Per Token Paid.
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    error UnauthorizedRewardsDistributor();
    error RewardAlreadyExists();

    constructor(address asset) {
        ASSET = IERC20(asset);
    }

    /// @notice Get reward rate 
    function getRewardRate(address token) public view returns (uint256) {
        return uint160(rewardData[token].packedData);
    }

    /// @notice Get rewards duration 
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32(rewardData[token].packedData >> 160);
    }

    /// @notice Get last update time 
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32(rewardData[token].packedData >> 192);
    }

    /// @notice Get period finish
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32(rewardData[token].packedData >> 224);
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        uint256 totalSupply = ASSET.totalSupply();
        if (totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return rewardData[_rewardsToken].rewardPerTokenStored
            + (
                (lastTimeRewardApplicable(_rewardsToken) - getLastUpdateTime(_rewardsToken)) * getRewardRate(_rewardsToken)
                    * 1e18 / totalSupply
            );
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        uint256 userRewardData_ = userRewardData[account][_rewardsToken];
        uint256 claimable = userRewardData_ >> 128;
        uint256 newEarned = ASSET.balanceOf(account)
            * (rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[account][_rewardsToken]) / 1e18;
        return claimable + newEarned;
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
    }

    function notifyRewardAmount(address _rewardsToken, uint256 reward) external {
        _updateReward(address(0));

        if (rewardData[_rewardsToken].rewardsDistributor != msg.sender) revert UnauthorizedRewardsDistributor();
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

        // Pack the new data
        uint256 packedData = uint256(newRewardRate) | (uint256(rewardsDuration) << 160) | (uint256(currentTime) << 192)
            | (uint256(currentTime + rewardsDuration) << 224);

        rewardData[_rewardsToken].packedData = packedData;
    }

    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);

            uint32 currentTime = uint32(block.timestamp);

            rewardData[token].packedData =
                (rewardData[token].packedData & ~(uint256(type(uint32).max) << 192)) | (uint256(currentTime) << 192);

            if (account != address(0)) {
                uint256 earnedAmount = earned(account, token);
                userRewardData[account][token] =
                    (earnedAmount << 128) | (userRewardData[account][token] & ((1 << 128) - 1));
                userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
    }
}