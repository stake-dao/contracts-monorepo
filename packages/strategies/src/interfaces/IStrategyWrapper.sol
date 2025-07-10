// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

interface IStrategyWrapper is IERC20, IERC20Metadata {
    // Deposit RewardVault shares
    function depositShares() external;
    function depositShares(uint256 amount) external;

    // Deposit RewardVault assets
    function depositAssets() external;
    function depositAssets(uint256 amount) external;

    // Withdraw underlying shares and burn wrapper tokens
    function withdraw() external;
    function withdraw(uint256 amount, address receiver) external;

    // Claim main reward token (e.g. CRV)
    function claim() external returns (uint256 amount);
    function claim(address receiver) external returns (uint256 amount);

    // Claim extra reward tokens
    function claimExtraRewards() external returns (uint256[] memory amounts);
    function claimExtraRewards(address[] calldata tokens) external returns (uint256[] memory amounts);
    function claimExtraRewards(address[] calldata tokens, address receiver)
        external
        returns (uint256[] memory amounts);

    /*──────────────────────────────────────────
      VIEW HELPERS
    ──────────────────────────────────────────*/
    function getPendingRewards(address user) external view returns (uint256 rewards);
    function getPendingExtraRewards(address user) external view returns (uint256[] memory rewards);
    function getPendingExtraRewards(address user, address token) external view returns (uint256 rewards);

    // Metadata
    function version() external pure returns (string memory);
}
