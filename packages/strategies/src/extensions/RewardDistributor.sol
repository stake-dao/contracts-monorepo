/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor {
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct Reward {
        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }

    /// @notice The asset being tracked by the reward distributor.
    IERC20 public immutable ASSET;

    mapping(address => Reward) public rewardData;

    /// @notice Active Reward Tokens.
    address[] public rewardTokens;

    /// @notice User Reward Per Token Paid.
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    /// @notice User Earned Rewards.
    mapping(address => mapping(address => uint256)) public rewards;

    constructor(address asset) {
        ASSET = IERC20(asset);
    }

    /// @notice Custom errors
    error RewardAlreadyExists();
    error UnauthorizedRewardsDistributor();

    function addReward(address _rewardsToken, address _rewardsDistributor, uint256 _rewardsDuration) public {
        if (rewardData[_rewardsToken].rewardsDuration != 0) revert RewardAlreadyExists();
        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        if (ASSET.totalSupply() == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return rewardData[_rewardsToken].rewardPerTokenStored
            + (
                (lastTimeRewardApplicable(_rewardsToken) - rewardData[_rewardsToken].lastUpdateTime)
                    * rewardData[_rewardsToken].rewardRate * 1e18 / ASSET.totalSupply()
            );
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        return ASSET.balanceOf(account)
            * (rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[account][_rewardsToken]) / 1e18
            + rewards[account][_rewardsToken];
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate * rewardData[_rewardsToken].rewardsDuration;
    }

    function notifyRewardAmount(address _rewardsToken, uint256 reward) external {
        _updateReward(address(0));

        if (rewardData[_rewardsToken].rewardsDistributor != msg.sender) revert UnauthorizedRewardsDistributor();
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= rewardData[_rewardsToken].periodFinish) {
            rewardData[_rewardsToken].rewardRate = reward / rewardData[_rewardsToken].rewardsDuration;
        } else {
            uint256 remaining = rewardData[_rewardsToken].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[_rewardsToken].rewardRate;
            rewardData[_rewardsToken].rewardRate = reward + leftover / rewardData[_rewardsToken].rewardsDuration;
        }

        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp + rewardData[_rewardsToken].rewardsDuration;
    }

    function _updateReward(address account) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
    }
}
