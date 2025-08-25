// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BaseOracle} from "src/integrations/curve/oracles/BaseOracle.sol";
import {ICurveCryptoSwapPool} from "src/interfaces/ICurvePool.sol";

/**
 * @title  CurveCryptoswapOracle
 * @notice Read-only price oracle that returns the value of one Curve
 *         **Crypto-swap** LP token expressed in an arbitrary **loan
 *         asset** (USDC, crvUSD, USDT, …).
 *
 *         The oracle is intended for lending markets (Morpho etc.) where the LP token is
 *         used as collateral and the loan asset is the unit in which debts are
 *         denominated.
 *
 *         Supported pool families: **Crypto Pool**, **TwoCrypto-NG**, and **TriCrypto-NG**
 *
 * @dev    Pricing formula
 *         ----------------
 *             Price(LP / Loan) = lp_price()                       ⎫ in token0
 *                               × Π price(hopᵢ)                   ⎬ token0 → USD
 *                               ÷ price(Loan / USD)               ⎭ USD    → Loan
 *
 *         • Curve documentation guarantees that `lp_price()` is denominated in
 *           **the coin at index 0** of the pool.
 *         • `token0ToUsdFeeds` is an ordered array of Chainlink feeds that, hop
 *           by hop, convert token0 into USD. Each element consumes the output
 *           of the previous hop.
 *
 *         Flash-manipulation caveat
 *         -------------------------------------------
 *         This oracle implements conservative minimum pricing across all pool assets
 *         and is intended for high-TVL, curated pools only. While `lp_price()`
 *         could theoretically be manipulated, the multi-layer protections and economic
 *         barriers make such attacks practically infeasible for the target deployment.
 *         Conservative LLTV settings are still recommended for additional safety.
 *
 *         Feed availability and adapter pattern
 *         ------------------------------------
 *         When token0 ≠ loan asset, the oracle requires a hop-chain to convert token0 to USD.
 *         Each hop in the chain can return prices in any denomination - the chain composition
 *         determines the final USD conversion.
 *
 *         Optional Loan Asset Feed
 *         ------------------------------------
 *         When token0 = loan asset, no external feeds are required and the oracle
 *         provides direct pricing with optimal gas efficiency.
 *
 *         Limitations – Layer 2 sequencer availability
 *         -------------------------------------------
 *         This oracle lacks sequencer uptime validation for Layer 2 networks. Chainlink
 *         feeds on L2s can become stale if the sequencer goes down. For L2 deployments,
 *         consider wrapping this oracle to include Sequencer Uptime Data Feed checks.
 *         https://docs.chain.link/data-feeds/l2-sequencer-feeds
 */
contract CurveCryptoswapOracle is BaseOracle {
    constructor(
        address _curvePool,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetFeedHeartbeat,
        address[] memory _token0ToUsdFeeds,
        uint256[] memory _token0ToUsdHeartbeats
    )
        BaseOracle(
            _curvePool,
            _loanAsset,
            _loanAssetFeed,
            _loanAssetFeedHeartbeat,
            _token0ToUsdFeeds,
            _token0ToUsdHeartbeats
        )
    {}

    ///////////////////////////////////////////////////////////////
    // --- OVERRIDED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Gets the LP token price in token0 terms
    /// @return lpPrice The LP token price in token0 terms (18 decimals
    function _getLpPriceInCoin0() internal view override returns (uint256) {
        return ICurveCryptoSwapPool(CURVE_POOL).lp_price();
    }
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
