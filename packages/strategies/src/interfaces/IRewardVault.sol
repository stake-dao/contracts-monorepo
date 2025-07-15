// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";

/// @title IRewardVault
/// @notice Interface for the RewardVault contract
interface IRewardVault is IERC4626 {
    function addRewardToken(address rewardsToken, address distributor) external;

    function depositRewards(address _rewardsToken, uint128 _amount) external;

    function deposit(uint256 assets, address receiver, address referrer) external returns (uint256 shares);

    function deposit(address account, address receiver, uint256 assets, address referrer)
        external
        returns (uint256 shares);

    function claim(address[] calldata tokens, address receiver) external returns (uint256[] memory amounts);

    function claim(address account, address[] calldata tokens, address receiver)
        external
        returns (uint256[] memory amounts);

    function getRewardsDistributor(address token) external view returns (address);

    function getLastUpdateTime(address token) external view returns (uint32);

    function getPeriodFinish(address token) external view returns (uint32);

    function getRewardRate(address token) external view returns (uint128);

    function getRewardPerTokenStored(address token) external view returns (uint128);

    function getRewardPerTokenPaid(address token, address account) external view returns (uint128);

    function getClaimable(address token, address account) external view returns (uint128);

    function getRewardTokens() external view returns (address[] memory);

    function lastTimeRewardApplicable(address token) external view returns (uint256);

    function rewardPerToken(address token) external view returns (uint128);

    function earned(address account, address token) external view returns (uint128);

    function isRewardToken(address rewardToken) external view returns (bool);

    function resumeVault() external;

    function gauge() external view returns (address);

    function ACCOUNTANT() external view returns (IAccountant);

    function checkpoint(address account) external;

    function PROTOCOL_ID() external view returns (bytes4);
}
