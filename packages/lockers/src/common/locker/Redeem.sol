// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

//////////////////////////////////////////////////////
/// --- IMPORTS
//////////////////////////////////////////////////////

// External Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Access Control & Security
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

// Local Interfaces
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

/// @title  Redeem
/// @notice Allows users to redeem *sdTokens*—including staked balances—for the underlying
///         token at a fixed conversion rate. Any pending gauge rewards are forwarded to
///         the caller during redemption.
/// @dev    Ownership is transferred via the {Ownable2Step} pattern. The owner can sweep
///         leftover `token` only after a 365‑day cooldown starting from the first
///         successful redemption.
contract Redeem is Ownable2Step, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Token that users ultimately receive.
    address public immutable token;

    /// @notice sdToken that can be redeemed and burned.
    address public immutable sdToken;

    /// @notice Staking contract for `sdToken` balances.
    address public immutable sdTokenGauge;

    /// @notice Conversion rate between `sdToken` and `token` expressed with 1e18 precision.
    uint256 public immutable conversionRateWad;

    /// @notice The cooldown duration before the owner can retrieve unredeemed `token`.
    uint256 public immutable reedeemCooldownDuration;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    //////////////////////////////////////////////////////
    /// --- STORAGE
    //////////////////////////////////////////////////////

    /// @notice Whether the redeem function has been called.
    bool public isRedemptionFinalized;

    /// @notice Timestamp of the first `redeem()` call. Determines the cooldown window.
    uint256 public firstRedeemTimestamp;

    //////////////////////////////////////////////////////
    /// --- CUSTOM ERRORS
    //////////////////////////////////////////////////////

    error RedeemCooldown(); // Attempted owner retrieval before cooldown elapsed.
    error NothingToRedeem(); // Caller has no redeemable balance.
    error RedemptionFinalized(); // Redemption has already been finalized.

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when the owner retrieves unredeemed `token` from the contract.
    event Retrieved(address indexed owner, uint256 amount);

    /// @notice Emitted when a user redeems `sdAmount` sdTokens for `tokenAmount` underlying tokens.
    event Redeemed(address indexed user, uint256 sdAmount, uint256 tokenAmount);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @param _token           The underlying token to distribute.
    /// @param _sdToken         The sdToken wrapper to burn.
    /// @param _sdTokenGauge    The staking contract linked to `_sdToken`.
    /// @param _conversionRate  Conversion rate (1e18 precision) between `_sdToken` and `_token`.
    /// @param _redeemCooldownDuration The cooldown duration for the redeem function.
    /// @param _owner           Initial owner.
    constructor(
        address _token,
        address _sdToken,
        address _sdTokenGauge,
        uint256 _conversionRate,
        uint256 _redeemCooldownDuration,
        address _owner
    ) Ownable() {
        token = _token;
        sdToken = _sdToken;
        sdTokenGauge = _sdTokenGauge;
        conversionRateWad = _conversionRate;
        reedeemCooldownDuration = _redeemCooldownDuration;

        _transferOwnership(_owner);
    }

    //////////////////////////////////////////////////////
    /// --- REDEEM FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Redeems caller's unstaked *and* staked sdTokens for the underlying `token`.
    ///         Any gauge rewards are claimed directly to the caller.
    /// @dev    Non‑reentrant. Records `firstRedeemTimestamp` on the first successful call.
    function redeem() external nonReentrant {
        /// @dev This is to prevent redeeming after the cooldown period has elapsed.
        if (isRedemptionFinalized) revert RedemptionFinalized();

        // 1. Record the redemption start time (for owner cooldown) if not set.
        if (firstRedeemTimestamp == 0) firstRedeemTimestamp = block.timestamp;

        uint256 sdAmount;

        // 2. Pull caller's unstaked sdTokens.
        uint256 balance = IERC20(sdToken).balanceOf(msg.sender);
        if (balance > 0) {
            IERC20(sdToken).safeTransferFrom(msg.sender, address(this), balance);
            sdAmount = balance;
        }

        // 3. Handle caller's staked balance in the gauge.
        uint256 gaugeBalance = IERC20(sdTokenGauge).balanceOf(msg.sender);
        if (gaugeBalance > 0) {
            // Claim rewards directly to the user.
            ILiquidityGauge(sdTokenGauge).claim_rewards(msg.sender);

            // Transfer gauge shares and withdraw underlying sdTokens.
            IERC20(sdTokenGauge).safeTransferFrom(msg.sender, address(this), gaugeBalance);
            ILiquidityGauge(sdTokenGauge).withdraw(gaugeBalance, false);

            unchecked {
                sdAmount += gaugeBalance;
            }
        }

        // 4. Ensure there is something to redeem.
        if (sdAmount == 0) revert NothingToRedeem();

        // 5. Burn sdTokens now held by this contract.
        ISdToken(sdToken).burn(address(this), sdAmount);

        // 6. Calculate and transfer the corresponding underlying tokens.
        uint256 tokenAmount = sdAmount.mulDiv(conversionRateWad, 1e18);
        IERC20(token).safeTransfer(msg.sender, tokenAmount);

        emit Redeemed(msg.sender, sdAmount, tokenAmount);
    }

    /// @notice Allows the owner to retrieve unredeemed `token` *after* the cooldown period.
    function retrieve() external onlyOwner {
        if (block.timestamp < firstRedeemTimestamp + reedeemCooldownDuration) revert RedeemCooldown();

        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Retrieved(msg.sender, amount);

        isRedemptionFinalized = true;
    }
}
