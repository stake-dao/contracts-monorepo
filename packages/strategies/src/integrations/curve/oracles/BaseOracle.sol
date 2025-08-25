// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

/// @title BaseOracle
abstract contract BaseOracle is IOracle {
    ///////////////////////////////////////////////////////////////
    // --- IMMUTABLES & STORAGE
    ///////////////////////////////////////////////////////////////

    // Crypto-swap pools
    address public immutable CURVE_POOL;

    // Loan asset of the lending market (e.g., USDC, crvUSD).
    IERC20Metadata public immutable LOAN_ASSET;
    IChainlinkFeed public immutable LOAN_ASSET_FEED;
    uint8 public immutable LOAN_ASSET_FEED_DECIMALS;
    uint256 public immutable LOAN_ASSET_FEED_HEARTBEAT;

    // ---------------------------------------------------------------------
    // SCALE FACTOR
    // ---------------------------------------------------------------------
    // Lending protocols such as Morpho Blue require oracle prices to be scaled
    // by `ORACLE_BASE_EXPONENT` and adjusted for the difference in token decimals between
    // the loan asset (debt unit) and the collateral asset (wrapped Curve LP token).
    //
    // The scale factor calculation follows Morpho's official Chainlink oracle approach:
    // SCALE_FACTOR = 1e(36 + loanDecimals + loanFeedDecimals - collateralDecimals - sum(token0FeedDecimals))
    //
    // This matches Morpho's formula: 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2)
    // Where in our case:
    // - dQ1 = loan asset decimals
    // - fpQ1 = loan asset feed decimals (only one quote feed)
    // - fpQ2 = 0 (no second quote feed)
    // - dB1 = collateral token decimals
    // - fpB1, fpB2, etc. = token0ToUsdFeeds decimals (base feeds)
    //
    // This ensures proper precision handling and matches Morpho's expected format exactly.
    // ---------------------------------------------------------------------
    uint256 public immutable SCALE_FACTOR;
    uint256 public constant ORACLE_BASE_EXPONENT = 36;

    // Feeds that turn token0 into USD (ordered hops).
    IChainlinkFeed[] public token0ToUsdFeeds;
    uint256[] public token0ToUsdHeartbeats;

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    error InvalidPrice();
    error InvalidDecimals();
    error ZeroAddress();
    error ZeroUint256();
    error ArrayLengthMismatch();
    error LoanAssetFeedRequired();

    ///////////////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @param _curvePool Address of the Crypto-swap pool.
    /// @param _loanAsset Address of the loan asset.
    /// @param _loanAssetFeed Chainlink feed for the loan asset if needed (e.g., USDC/USD, crvUSD/USD, USDT/USD, etc.).
    /// @param _loanAssetFeedHeartbeat Max seconds between two updates of the loan asset feed.
    /// @param _token0ToUsdFeeds Ordered feeds to convert token0 to USD.
    /// @param _token0ToUsdHeartbeats Max seconds between two updates of each feed.
    /// @custom:reverts ZeroAddress if `_curvePool`, `_loanAsset` is the zero address.
    /// @custom:reverts ZeroUint256 if `_loanAssetFeedHeartbeat` is zero.
    /// @custom:reverts ArrayLengthMismatch if `_token0ToUsdFeeds` and `_token0ToUsdHeartbeats` have different lengths.
    /// @dev If `_loanAssetFeed` is the zero address, it means that the loan asset is the coins0 of the pool.
    ///      In this case, there is no need to set up the loan asset feed data (_loanAssetFeed, _loanAssetFeedDecimals, _loanAssetFeedHeartbeat).
    constructor(
        address _curvePool,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetFeedHeartbeat,
        address[] memory _token0ToUsdFeeds,
        uint256[] memory _token0ToUsdHeartbeats
    ) {
        require(_curvePool != address(0), ZeroAddress());
        require(_loanAsset != address(0), ZeroAddress());
        require(_token0ToUsdFeeds.length == _token0ToUsdHeartbeats.length, ArrayLengthMismatch());

        CURVE_POOL = _curvePool;
        LOAN_ASSET = IERC20Metadata(_loanAsset);

        // Calculate the total decimals of the token0ToUsdFeeds for the calculation of the scale factor
        // and set up the loan asset feed data if needed
        bool isCoin0LoanAsset = (_loanAssetFeed == address(0) && _loanAssetFeedHeartbeat == 0);
        if (isCoin0LoanAsset) {
            // Validate that coin0 actually equals loan asset. If so, we can avoid setting up the loan asset feed data
            require(ICurvePool(_curvePool).coins(0) == _loanAsset, LoanAssetFeedRequired());
        } else {
            // Set up feeds for conversion case
            require(_loanAssetFeed != address(0), ZeroAddress());
            require(_loanAssetFeedHeartbeat != 0, ZeroUint256());
            LOAN_ASSET_FEED = IChainlinkFeed(_loanAssetFeed);
            LOAN_ASSET_FEED_DECIMALS = IChainlinkFeed(_loanAssetFeed).decimals();
            LOAN_ASSET_FEED_HEARTBEAT = _loanAssetFeedHeartbeat;
        }

        // Fetch it either by requesting the pool or his associated LP token when different
        uint256 collateralDecimals;
        try IERC20Metadata(_curvePool).decimals() returns (uint8 decimals) {
            collateralDecimals = decimals;
        } catch {
            collateralDecimals = IERC20Metadata(ICurvePool(_curvePool).token()).decimals();
        }
        require(collateralDecimals > 0, InvalidDecimals());

        uint256 loanDecimals = IERC20Metadata(_loanAsset).decimals();
        require(loanDecimals > 0, InvalidDecimals());

        // Scale factor calculation following Morpho's exact approach:
        // Morpho's formula: SCALE_FACTOR = 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2)
        //
        // In our case:
        // - dQ1 = loan asset decimals
        // - fpQ1 = loan asset feed decimals (only one quote feed)
        // - fpQ2 = 0 (no second quote feed)
        // - dB1 = collateral token decimals
        // - fpB1, fpB2, etc. = token0ToUsdFeeds decimals (base feeds)
        //
        // SCALE_FACTOR = 1e(36 + loanDecimals + loanFeedDecimals - collateralDecimals)
        SCALE_FACTOR = 10 ** (ORACLE_BASE_EXPONENT + loanDecimals + LOAN_ASSET_FEED_DECIMALS - collateralDecimals);

        // Set the conversion feeds required to denominate token0 in loan asset (hop-by-hop) if needed
        for (uint256 i; i < _token0ToUsdFeeds.length; i++) {
            // Each hop must be a real Chainlink feed and have a non-zero heartbeat
            require(_token0ToUsdFeeds[i] != address(0), ZeroAddress());
            require(_token0ToUsdHeartbeats[i] != 0, ZeroUint256());

            token0ToUsdFeeds.push(IChainlinkFeed(_token0ToUsdFeeds[i]));
            token0ToUsdHeartbeats.push(_token0ToUsdHeartbeats[i]);
        }
    }

    /// @notice Price of 1 LP token in the loan asset, scaled to 1e36.
    function price() external view returns (uint256) {
        uint256 lpInCoin0 = _getLpPriceInCoin0();
        //      (18 decimals)            └─ raw LP price in token0 terms

        // If there is no loan asset feed, it means token0 equals loan asset,
        // so we can scale the returned price directly
        if (LOAN_ASSET_FEED == IChainlinkFeed(address(0))) return Math.mulDiv(lpInCoin0, SCALE_FACTOR, 1e18);

        // Numerator: LP price in token0 × all token0→USD feeds (keep raw feed decimals)
        uint256 numerator = lpInCoin0;
        uint256 length = token0ToUsdFeeds.length;
        for (uint256 i; i < length; i++) {
            uint256 feedPrice = _fetchFeedPrice(token0ToUsdFeeds[i], token0ToUsdHeartbeats[i]);
            uint256 feedDecimals = token0ToUsdFeeds[i].decimals();
            numerator = Math.mulDiv(numerator, feedPrice, 10 ** feedDecimals);
        }

        // Denominator: loan asset feed price (USD per loan asset)
        uint256 denominator = _fetchFeedPrice(LOAN_ASSET_FEED, LOAN_ASSET_FEED_HEARTBEAT);

        // Apply scale factor and cancel lpInCoin0's 1e18
        // lpInCoin0 is 18-decimal; SCALE_FACTOR already normalizes feed precisions to the
        // 36 + loanDecimals − collateralDecimals target. Divide by 1e18 to remove lpInCoin0's
        // extra 18-dec so the final result matches Morpho's expected scaling.
        return Math.mulDiv(numerator, SCALE_FACTOR, denominator) / 1e18;
    }

    /// @notice Fetches the price from a Chainlink feed
    /// @param feed The Chainlink feed to fetch the price from.
    /// @param maxStale The maximum number of seconds since the last update of the feed.
    /// @return price The raw price returned by the feed (native feed decimals).
    /// @custom:reverts InvalidPrice if the price fetched from the Chainlink feeds are invalid (not positive) or stale.
    function _fetchFeedPrice(IChainlinkFeed feed, uint256 maxStale) internal view returns (uint256) {
        (, int256 latestPrice,, uint256 updatedAt,) = feed.latestRoundData();
        require(latestPrice > 0 && updatedAt > block.timestamp - maxStale, InvalidPrice());
        return uint256(latestPrice);
    }

    ///////////////////////////////////////////////////////////////
    // --- VIRTUAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Gets the LP token price in token0 terms
    /// @return lpPrice The LP token price in token0 terms (18 decimals
    function _getLpPriceInCoin0() internal view virtual returns (uint256);
}

/*
──────────────────────────────────────────────────────────────────────────────
EXAMPLES – how to build the **token0 → USD** feed chain
──────────────────────────────────────────────────────────────────────────────
The critical constructor inputs are the two *parallel* arrays:

    address[]  token0ToUsdFeeds
    uint256[]  token0ToUsdHeartbeats

Each element `feeds[i]` converts the *output* of the previous hop into the
*input* of the next hop, until the value is finally expressed in **USD**. For
lending markets that borrow **USDC**, you then pass the USDC/USD feed via the
dedicated `loanAssetFeed` parameter.

IMPORTANT: The oracle uses Curve's `lp_price()` for conservative pricing.
When token0 = loan asset, no external feeds are required for optimal gas efficiency.

---------------------------------------------------------------------
1.  TriCrypto-USDC pool  → token0 = USDC
---------------------------------------------------------------------
• Pool assets: USDC, wBTC, WETH
• token0 = USDC (loan asset)
• No conversion needed: direct pricing

      token0ToUsdFeeds       = []                    // Empty array
      token0ToUsdHeartbeats  = []                    // Empty array
      loanAssetFeed          = address(0)            // No feed needed

The oracle fetches the LP price directly from Curve's `lp_price()` and scales it.

---------------------------------------------------------------------
2.  TriCrypto-USDT pool  (USDT / wBTC / WETH)   → token0 = USDT
---------------------------------------------------------------------
• Pool assets: USDT, wBTC, WETH
• token0 = USDT (≠ loan asset USDC)
• Need to convert USDT → USD → USDC

      token0ToUsdFeeds       = [USDT/USD feed]
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The USDT/USD feed is mandatory so the oracle reacts to any USDT de-peg.

---------------------------------------------------------------------
3.  WETH / RSUP pool  → token0 = WETH
---------------------------------------------------------------------
• Pool assets: WETH, RSUP
• token0 = WETH (≠ loan asset USDC)
• WETH is a **1:1 non-rebasing wrapper** around ETH
• Need to convert WETH → ETH → USD → USDC

      token0ToUsdFeeds       = [ETH/USD feed]        // Skip WETH/ETH hop (1:1)
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

Because WETH unwraps 1:1 into ETH, the single ETH/USD feed converts token0 to USD.

---------------------------------------------------------------------
4.  swETH / frxETH pool  → token0 = swETH
---------------------------------------------------------------------
• Pool assets: swETH, frxETH
• token0 = swETH (≠ loan asset USDC)
• swETH is a liquid staking derivative of ETH
• Need to convert swETH → ETH → USD → USDC (because there is no swETH/USD feed)

      token0ToUsdFeeds       = [swETH/ETH feed, ETH/USD feed]
      token0ToUsdHeartbeats  = [1 days, 1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle converts swETH to USDC via the hop chain: swETH → ETH → USD → USDC.
This handles the case where liquid staking derivatives don't have direct USD feeds.

---------------------------------------------------------------------
5.  FRAX / USDC pool  → token0 = FRAX
---------------------------------------------------------------------
• Pool assets: FRAX, USDC
• token0 = FRAX (≠ loan asset USDC)
• Need to convert FRAX → USD → USDC

      token0ToUsdFeeds       = [FRAX/USD feed]
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle converts FRAX to USDC to handle potential FRAX de-peg scenarios.
*/
