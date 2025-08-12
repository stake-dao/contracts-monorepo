// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseOracle} from "src/integrations/curve/oracles/BaseOracle.sol";
import {ICurveStableSwapPool} from "src/interfaces/ICurvePool.sol";

/**
 * @title  CurveStableswapOracle
 * @notice Read-only price oracle that returns the value of one Curve
 *         **StableSwap** LP token expressed in an arbitrary **loan
 *         asset** (USDC, crvUSD, USDT, …).
 *
 *         The oracle is intended for lending markets (Morpho etc.) where the LP token is
 *         used as collateral and the loan asset is the unit in which debts are
 *         denominated.
 *
 *         Supported pool families: **StableSwap** pools and **StableSwap-NG** pools
 *         that implement the `price_oracle()` method.
 *
 * @dev    Pricing formula
 *         ----------------
 *             Price(LP / Loan) = min(price_oracle(i)) × get_virtual_price()    ⎫ in coin0
 *                               × Π price(hopᵢ)                                ⎬ coin0 → USD
 *                               ÷ price(Loan / USD)                            ⎭ USD    → Loan
 *
 *         • Uses Curve's EMA price oracle for conservative pricing across all pool assets
 *         • `price_oracle(i)` returns the price of coin[i+1] relative to coin0 (18 decimals)
 *         • `get_virtual_price()` returns the LP token price in coin0 terms (18 decimals)
 *         • `token0ToUsdFeeds` is an ordered array of Chainlink feeds that, hop by hop,
 *           convert coin0 into USD. Each element consumes the output of the previous hop.
 *
 *         Flash-manipulation caveat
 *         -------------------------------------------
 *         This oracle leverages Curve's battle-tested EMA price oracle which provides
 *         protection against flash loan attacks through exponential moving average smoothing.
 *         The conservative minimum pricing across all pool assets prevents overvaluation
 *         during asset depegs. This oracle is intended for high-TVL, curated pools only.
 *         Conservative LLTV settings are still recommended for additional safety.
 *
 *         Feed availability and adapter pattern
 *         ------------------------------------
 *         When coin0 ≠ loan asset, the oracle requires a hop-chain to convert coin0 to USD.
 *         Each hop in the chain can return prices in any denomination - the chain composition
 *         determines the final USD conversion.
 *
 *         Optional Loan Asset Feed
 *         ------------------------------------
 *         When coin0 = loan asset, no external feeds are required and the oracle
 *         provides direct pricing with optimal gas efficiency.
 *
 *         Limitations – Pool Compatibility
 *         -------------------------------------------
 *         This oracle only supports pools that implement the `price_oracle()` method.
 *         Pools without this method are incompatible and will revert during deployment.
 *         The oracle automatically detects pool configuration and supports both:
 *         • 2-coin pools: `price_oracle()` (no arguments)
 *         • Multi-coin pools: `price_oracle(i)` (with coin index argument)
 *
 *         Limitations – Layer 2 sequencer availability
 *         -------------------------------------------
 *         This oracle lacks sequencer uptime validation for Layer 2 networks. Chainlink
 *         feeds on L2s can become stale if the sequencer goes down. For L2 deployments,
 *         consider wrapping this oracle to include Sequencer Uptime Data Feed checks.
 *         https://docs.chain.link/data-feeds/l2-sequencer-feeds
 *
 *
 *         When coin0 = loan asset, no external feeds are required and the oracle
 *         provides direct pricing with optimal gas efficiency.
 */
contract CurveStableswapOracle is BaseOracle {
    /// @dev Define if the price_oracle() method takes no arguments
    bool internal immutable NO_ARGUMENT;
    /// @dev Define the number of coins in the pool
    uint256 internal immutable N_COINS;

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    error PoolMustHaveAtLeast2Coins();
    error PoolDoesNotSupportPriceOracle();
    error PoolIncompatiblePriceOracleImplementation();

    /// @param _curvePool The address of the Curve pool for the LP token collateral.
    /// @param _collateralToken The address of the collateral token of the lending market.
    /// @param _loanAsset The address of the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeed The address of the Chainlink feed for the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeedHeartbeat The maximum number of seconds since the last update of the loan asset feed.
    /// @param _token0ToUsdFeeds Ordered feeds to convert token0 to USD.
    /// @param _token0ToUsdHeartbeats Max seconds between two updates of each feed.
    /// @custom:reverts ZeroAddress if `_curvePool`, `_collateralToken`, `_loanAsset`, or `_loanAssetFeed` is the zero address.
    /// @custom:reverts ZeroUint256 if `_loanAssetFeedHeartbeat` is zero or if no pool asset feeds are provided.
    /// @custom:reverts ArrayLengthMismatch if feed and heartbeat arrays have different lengths.
    constructor(
        address _curvePool,
        address _collateralToken,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetFeedHeartbeat,
        address[] memory _token0ToUsdFeeds,
        uint256[] memory _token0ToUsdHeartbeats
    )
        BaseOracle(
            _curvePool,
            _collateralToken,
            _loanAsset,
            _loanAssetFeed,
            _loanAssetFeedHeartbeat,
            _token0ToUsdFeeds,
            _token0ToUsdHeartbeats
        )
    {
        (N_COINS, NO_ARGUMENT) = _detectPoolConfiguration(_curvePool);
    }

    ///////////////////////////////////////////////////////////////
    // --- OVERRIDED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Gets the LP token price in coin0 terms using Curve's EMA price oracle
    /// @return lpPrice The LP token price in coin0 terms (18 decimals)
    function _getLpPriceInCoin0() internal view override returns (uint256) {
        uint256 minPrice = 1e18;

        // Get minimum price across all coins (excluding coin0)
        for (uint256 i; i < N_COINS - 1; i++) {
            uint256 _price = NO_ARGUMENT
                ? ICurveStableSwapPool(CURVE_POOL).price_oracle()
                : ICurveStableSwapPool(CURVE_POOL).price_oracle(i);
            if (_price < minPrice) minPrice = _price;
        }

        // Multiply by virtual price to get LP price in coin0 terms
        return Math.mulDiv(minPrice, ICurveStableSwapPool(CURVE_POOL).get_virtual_price(), 1e18);
        // (18 dec)            └─ minPrice(18-dec) × virtualPrice(18-dec) / 1e18
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Detects the pool configuration by testing price_oracle() calls
    /// @param pool The Curve pool address
    /// @return nCoins Number of coins in the pool
    /// @return noArgument Whether price_oracle() takes no arguments
    function _detectPoolConfiguration(address pool) internal view returns (uint256 nCoins, bool noArgument) {
        // Find N_COINS by calling coins(i) until it fails. This is the universal way to detect the number of coins in all pool
        for (uint256 i; i <= 8; i++) {
            try ICurveStableSwapPool(pool).coins(i) returns (address) {
                // Coin exists, continue
            } catch {
                require(i > 1, PoolMustHaveAtLeast2Coins());
                nCoins = i;
                break;
            }
        }

        // Test price_oracle() signature
        for (uint256 i; i < nCoins - 1; i++) {
            try ICurveStableSwapPool(pool).price_oracle(i) returns (uint256 _price) {
                require(_price > 0, InvalidPrice());
                // Method takes argument, continue testing
            } catch {
                // Method doesn't take any arguments, verify it's a 2-coin pool
                require(i == 0 && nCoins == 2, PoolIncompatiblePriceOracleImplementation());

                // Test the no-argument version
                try ICurveStableSwapPool(pool).price_oracle() returns (uint256 _price) {
                    require(_price > 0, InvalidPrice());
                    noArgument = true;
                } catch {
                    revert PoolDoesNotSupportPriceOracle();
                }
                break;
            }
        }
    }
}

/*───────────────────────────────────────────────────────────────────────────
EXAMPLES – configuring coin0 to USD conversion feeds
─────────────────────────────────────────────────────────────────────────────
Constructor signature

    CurveStableswapOracle(
        curvePool,
        collateralToken,           // LP token or wrapper
        loanAsset,                 // USDC in the examples below
        loanAssetFeed,             // USDC/USD Chainlink feed (optional)
        loanAssetHeartbeat,        // Heartbeat for loan asset feed (optional)
        token0ToUsdFeeds,          // Array of feeds to convert coin0 to USD (optional)
        token0ToUsdHeartbeats      // Array of heartbeats for each feed (optional)
    )

IMPORTANT: The oracle uses Curve's EMA price oracle for conservative pricing.
The minimum price across all pool assets (excluding coin0) is used to prevent
overvaluation during asset depegs.

---------------------------------------------------------------------
1.  USDC / USDT  **StableSwap** pool → coin0 = USDC
---------------------------------------------------------------------
• Pool assets: USDC, USDT
• coin0 = USDC (loan asset)
• No conversion needed: direct pricing

      token0ToUsdFeeds       = []                    // Empty array
      token0ToUsdHeartbeats  = []                    // Empty array
      loanAssetFeed          = address(0)            // No feed needed
      loanAssetHeartbeat     = 0                     // No heartbeat needed

The oracle fetches the LP price directly from Curve's price oracle and scales it.

---------------------------------------------------------------------
2.  USDT / DAI  **StableSwap** pool → coin0 = USDT
---------------------------------------------------------------------
• Pool assets: USDT, DAI
• coin0 = USDT (≠ loan asset USDC)
• Need to convert USDT → USD → USDC

      token0ToUsdFeeds       = [USDT/USD feed]
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle uses Curve's minimum price (USDT vs DAI) and converts USDT to USDC.

---------------------------------------------------------------------
3.  wstETH / wETH  **StableSwap-NG** pool → coin0 = wstETH
---------------------------------------------------------------------
• Pool assets: wstETH, wETH
• coin0 = wstETH (≠ loan asset USDC)
• Need to convert wstETH → USD → USDC

      token0ToUsdFeeds       = [wstETH/USD feed]
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle uses Curve's minimum price (wstETH vs wETH) and converts wstETH to USDC.

---------------------------------------------------------------------
4.  mBTC / wBTC  **StableSwap** pool → coin0 = mBTC
---------------------------------------------------------------------
• Pool assets: mBTC, wBTC
• coin0 = mBTC (≠ loan asset USDC)
• Need to convert mBTC → BTC → USD → USDC (because there is no mBTC/USD feed)

      token0ToUsdFeeds       = [mBTC/BTC feed, BTC/USD feed]
      token0ToUsdHeartbeats  = [1 days, 1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle uses Curve's minimum price (mBTC vs wBTC) and converts mBTC to USDC
via the hop chain: mBTC → BTC → USD → USDC.

---------------------------------------------------------------------
5.  FRAX / USDC  **StableSwap** pool → coin0 = FRAX
---------------------------------------------------------------------
• Pool assets: FRAX, USDC
• coin0 = FRAX (≠ loan asset USDC)
• Need to convert FRAX → USD → USDC

      token0ToUsdFeeds       = [FRAX/USD feed]
      token0ToUsdHeartbeats  = [1 days]
      loanAssetFeed          = USDC/USD feed
      loanAssetHeartbeat     = 1 days

The oracle uses Curve's minimum price (FRAX vs USDC) and converts FRAX to USDC.
*/
