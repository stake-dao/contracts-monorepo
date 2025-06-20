// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @title IMorphoStrategyWrapper
/// @notice ERC-20–compatible wrapper for Stake DAO RewardVault shares,
///         exposing the extra deposit/withdraw/claim helpers used by Morpho.
interface IMorphoStrategyWrapper is IERC20, IERC20Metadata {
    // Deposit RewardVault shares and mint wrapper tokens (1:1)
    function deposit() external;
    function deposit(uint256 amount) external;

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
