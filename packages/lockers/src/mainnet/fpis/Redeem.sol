// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

contract Redeem {
    using SafeERC20 for IERC20;

    /// @notice The token to receive.
    address public immutable token;

    /// @notice The sdToken to redeem.
    address public immutable sdToken;

    /// @notice The sdToken staking contract.
    address public immutable sdTokenGauge;

    error NothingToRedeem();

    event RedeemedAmount(address indexed user, uint256 amount);

    constructor(address _token, address _sdToken, address _sdTokenGauge) {
        token = _token;
        sdToken = _sdToken;
        sdTokenGauge = _sdTokenGauge;
    }

    /// @notice Redeems all sdTokens and gauge shares from msg.sender.
    ///         Claims gauge rewards to msg.sender if they exist.
    ///         Burns the redeemed sdTokens and sends the underlying tokens to msg.sender.
    function redeem() external {
        // 1. Transfer sdTokens from user -> contract
        uint256 redeemAmount = IERC20(sdToken).balanceOf(msg.sender);

        if (redeemAmount > 0) {
            IERC20(sdToken).safeTransferFrom(msg.sender, address(this), redeemAmount);
        }

        // 2. Unstake from gauge: claim rewards + withdraw
        uint256 sdTokenGaugeBalance = ILiquidityGauge(sdTokenGauge).balanceOf(msg.sender);
        if (sdTokenGaugeBalance > 0) {
            // Claim rewards to msg.sender (check how your gauge handles this)
            ILiquidityGauge(sdTokenGauge).claim_rewards(msg.sender);

            // Transfer gauge shares user->contract
            IERC20(sdTokenGauge).safeTransferFrom(msg.sender, address(this), sdTokenGaugeBalance);

            // Withdraw staked tokens from gauge to this contract
            ILiquidityGauge(sdTokenGauge).withdraw(sdTokenGaugeBalance, false);

            // Add the gauge balance to the redeem amount
            redeemAmount += sdTokenGaugeBalance;
        }

        // 3. Check if there is anything to redeem
        if (redeemAmount == 0) revert NothingToRedeem();

        // 4. Burn sdTokens
        ISdToken(sdToken).burn(address(this), redeemAmount);

        // 5. Transfer underlying to user
        IERC20(token).safeTransfer(msg.sender, redeemAmount);

        emit RedeemedAmount(msg.sender, redeemAmount);
    }
}
