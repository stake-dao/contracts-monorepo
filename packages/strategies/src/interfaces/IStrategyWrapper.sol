// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";

interface IStrategyWrapper is IERC20, IERC20Metadata {
    function REWARD_VAULT() external view returns (IRewardVault);
    function LENDING_PROTOCOL() external view returns (address);

    // Deposit
    function depositShares() external;
    function depositShares(uint256 amount) external;
    function depositAssets() external;
    function depositAssets(uint256 amount) external;

    // Withdraw
    function withdraw() external;
    function withdraw(uint256 amount) external;

    // Claim main reward token (e.g. CRV)
    function claim() external returns (uint256 amount);
    function claimExtraRewards() external returns (uint256[] memory amounts);
    function claimExtraRewards(address[] calldata tokens) external returns (uint256[] memory amounts);

    // Liquidation
    function claimLiquidation(address liquidator, address victim, uint256 liquidatedAmount) external;

    /*──────────────────────────────────────────
      VIEW HELPERS
    ──────────────────────────────────────────*/
    function getPendingRewards(address user) external view returns (uint256 rewards);
    function getPendingExtraRewards(address user) external view returns (uint256[] memory rewards);
    function getPendingExtraRewards(address user, address token) external view returns (uint256 rewards);
    function lendingMarketId() external view returns (bytes32);

    // Owner
    function initialize(bytes32 marketId) external;
}
