// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurveStableSwapPool} from "src/interfaces/ICurvePool.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

/**
 * @title  CurveStableswapOracle
 * @notice Read-only price oracle that returns the **USD value (18 decimals)** of one Curve
 *         StableSwap LP token (or any token that is strictly pegged 1:1 to that LP token).
 *
 *         The oracle is intended for lending markets (Morpho etc.) where the LP token is used as
 *         collateral and the "loan asset" (e.g. USDC, crvUSD) is the unit in which debts are denominated.
 *
 *         Supported pool families: classic **StableSwap** pools and the **patched StableSwap-NG**
 *         implementation. Legacy NG pools listed in Curve's public spreadsheet are incompatible
 *         as explained below.
 *
 * @dev    Pricing formula
 *         ----------------
 *             Price(LP / Loan) = Price(LP / Peg) * Price(Peg / USD)
 *                                   --------------------------------
 *                                       Price(Loan / USD)
 *
 *         where  - *Peg*  is the **unit-of-account** of the StableSwap pool:
 *                   - USD for the vast majority of stablecoin pools
 *                   - ETH for wstETH/wETH, sfrxETH/frxETH, etc.
 *                   - BTC for tBTC/wBTC, etc.
 *
 *         A Chainlink feed providing *Peg/USD* is required when `Peg != USD`; otherwise the
 *         the peg price is assumed to be 1 USD. The loan-asset feed **must always be X/USD**
 *         where X is the loan token used in the lending market.
 *
 *         Flash-manipulation caveat
 *         -------------------------------------------
 *         This oracle implements conservative minimum pricing across all pool assets
 *         and is intended for high-TVL, curated pools only. While `get_virtual_price()`
 *         could theoretically be manipulated, the multi-layer protections and economic
 *         barriers make such attacks practically infeasible for the target deployment.
 *         Conservative LLTV settings are still recommended for additional safety.
 *
 *         Limitations – StableSwap-NG mixed-precision pools
 *         ------------------------------------------------
 *         Curve has disclosed a bug in one outdated **StableSwap-NG** template where
 *         `get_virtual_price()` can jump sharply if the pool's tokens do not
 *         all share 18 decimals **or** rely on the `external_rate` mechanism
 *         Examples include `USDe/USDC` or `pyUSD/USDC` and other 18-vs-6 decimal pairs.
 *         - https://docs.curve.finance/stableswap-exchange/stableswap-ng/pools/oracles/
 *         - https://docs.google.com/spreadsheets/d/130LPSQbAnMWTC1yVO23cqRSblrkYFfdHdRwYNpaaoYY
 *
 *         20 pools are known to be affected by this bug, all networks combined.
 *         This oracle is not intended for these pools.
 *
 *         Limitations – Layer 2 sequencer availability
 *         -------------------------------------------
 *         This oracle lacks sequencer uptime validation for Layer 2 networks. Chainlink
 *         feeds on L2s can become stale if the sequencer goes down. For L2 deployments,
 *         consider wrapping this oracle to include Sequencer Uptime Data Feed checks.
 *         https://docs.chain.link/data-feeds/l2-sequencer-feeds
 */
contract CurveStableswapOracle is IOracle {
    ///////////////////////////////////////////////////////////////
    // --- IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice Base exponent for the oracle price.
    uint256 public constant ORACLE_BASE_EXPONENT = 36;

    /// @notice Address of the Curve StableSwap pool.
    ICurveStableSwapPool public immutable CURVE_POOL;

    /// @notice Address of the loan asset of the lending market (e.g., USDC/crvUSD).
    IERC20Metadata public immutable LOAN_ASSET;

    /// @notice Address of the Chainlink price feed for the loan asset of the lending market (e.g., USDC/crvUSD).
    IChainlinkFeed public immutable LOAN_ASSET_FEED;

    /// @notice Decimals of the loan asset's price feed (e.g., 8 for Chainlink USD feeds).
    uint8 public immutable LOAN_ASSET_FEED_DECIMALS;

    /// @notice Maximum seconds between two updates of the loan asset feed.
    uint256 public immutable LOAN_ASSET_FEED_HEARTBEAT;

    /// @notice Chainlink feeds for each asset in the pool (all priced in USD)
    IChainlinkFeed[] public poolAssetFeeds;

    /// @notice Heartbeats for each pool asset feed
    uint256[] public poolAssetHeartbeats;

    /// @notice Pre-computed factor that scales the oracle output to `ORACLE_BASE_EXPONENT`.
    uint256 public immutable SCALE_FACTOR;

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @dev Thrown when the Chainlink feed returns a stale or invalid price.
    error InvalidPrice();
    error ZeroAddress();
    error ZeroUint256();
    error ArrayLengthMismatch();
    error InvalidDecimals();

    /// @param _curvePool The address of the Curve pool for the LP token collateral.
    /// @param _collateralToken The address of the collateral token of the lending market.
    /// @param _loanAsset The address of the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeed The address of the Chainlink feed for the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeedHeartbeat The maximum number of seconds since the last update of the loan asset feed.
    /// @param _poolAssetFeeds Array of Chainlink feeds for each asset in the pool (all priced in USD)
    /// @param _poolAssetHeartbeats Array of heartbeats for each pool asset feed
    /// @dev Given a LP/USDC lending market, where LP is the LP token of a Curve Stableswap Pool:
    //       - `_poolAssetFeeds` must contain one USD-denominated feed per pool asset for conservative pricing
    //         - For USDC/USDT pool: [USDC/USD, USDT/USD] feeds
    //         - For wstETH/wETH pool: [wstETH/USD, wETH/USD] feeds
    //         - For wBTC/tBTC pool: [wBTC/USD, tBTC/USD] feeds
    //       - The `loanAssetFeed` must track the price of the loan asset. In this case, it is USDC/USD. For LP/crvUSD, it would be crvUSD/USD.
    /// @custom:reverts ZeroAddress if `_curvePool`, `_collateralToken`, `_loanAsset`, or `_loanAssetFeed` is the zero address.
    /// @custom:reverts ZeroUint256 if `_loanAssetFeedHeartbeat` is zero or if no pool asset feeds are provided.
    /// @custom:reverts ArrayLengthMismatch if feed and heartbeat arrays have different lengths.
    /// @custom:reverts InvalidDecimals if any pool asset feed doesn't have 8 decimals.
    constructor(
        address _curvePool,
        address _collateralToken,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetFeedHeartbeat,
        address[] memory _poolAssetFeeds,
        uint256[] memory _poolAssetHeartbeats
    ) {
        require(
            _curvePool != address(0) && _collateralToken != address(0) && _loanAsset != address(0)
                && _loanAssetFeed != address(0),
            ZeroAddress()
        );
        require(_loanAssetFeedHeartbeat > 0, ZeroUint256());
        require(_poolAssetFeeds.length > 0, ZeroUint256());
        require(_poolAssetFeeds.length == _poolAssetHeartbeats.length, ArrayLengthMismatch());

        CURVE_POOL = ICurveStableSwapPool(_curvePool);

        LOAN_ASSET = IERC20Metadata(_loanAsset);
        LOAN_ASSET_FEED = IChainlinkFeed(_loanAssetFeed);
        LOAN_ASSET_FEED_DECIMALS = LOAN_ASSET_FEED.decimals();
        LOAN_ASSET_FEED_HEARTBEAT = _loanAssetFeedHeartbeat;

        // Store pool asset feeds (each asset priced in USD)
        uint256 length = _poolAssetFeeds.length;
        for (uint256 i; i < length; i++) {
            require(_poolAssetFeeds[i] != address(0), ZeroAddress());
            require(_poolAssetHeartbeats[i] > 0, ZeroUint256());

            // Ensure all USD feeds are 8 decimals
            IChainlinkFeed feed = IChainlinkFeed(_poolAssetFeeds[i]);
            require(feed.decimals() == 8, InvalidDecimals());
            poolAssetFeeds.push(feed);
            poolAssetHeartbeats.push(_poolAssetHeartbeats[i]);
        }

        // ---------------------------------------------------------------------
        // SCALE FACTOR
        // ---------------------------------------------------------------------
        // Lending protocols such as Morpho Blue require the oracle to return:
        //   realPrice * 1e36 * 10^(loanTokenDecimals - collateralTokenDecimals)
        //
        // The raw ratio we compute is:
        //   baseRatio  = LP/Peg (18 dec) * Peg/USD (fpBase) / Loan/USD (fpLoan)
        // which itself carries 18 + fpBase - fpLoan decimals.
        //
        // To reach the 1e36 scale **and** compensate for the token-decimal
        // difference we must multiply by 10^(36 + loanTokenDec + fpLoan −
        // collateralTokenDec − fpBase).
        //
        // That exponent is guaranteed to be non-negative for the pools this
        // oracle targets, so we can encode it directly in one `SCALE_FACTOR`.
        // ---------------------------------------------------------------------
        SCALE_FACTOR = 10
            ** (
                ORACLE_BASE_EXPONENT + LOAN_ASSET.decimals() + LOAN_ASSET_FEED_DECIMALS
                    - IERC20Metadata(_collateralToken).decimals() - 8
            );
    }

    /// @dev Math.mulDiv rounds toward zero (truncates) so the returned price is lower bound
    ///      It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    ///      10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    ///      decimals of precision.
    /// @return price the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @custom:reverts InvalidPrice if the price fetched from the Chainlink feeds are invalid (negative or 0)
    function price() external view returns (uint256) {
        // 1. Get the price of the LP token in its "unit of account" (assumes all assets are equal)
        uint256 priceLpInPeg = CURVE_POOL.get_virtual_price();

        // 2. Get the minimum asset price in USD
        uint256 minAssetPriceUsd = _getMinimumAssetPrice();

        // 3. Get the price of the loan asset in USD from its Chainlink feed.
        uint256 priceLoanInUsd = _fetchFeedPrice(LOAN_ASSET_FEED, LOAN_ASSET_FEED_HEARTBEAT);

        // 4. Aggregate and scale to 1e36 using the pre-computed SCALE_FACTOR.
        // Formula: price(LP/Loan) = (priceLpInPeg * minAssetPriceUsd / priceLoanInUsd) * SCALE_FACTOR
        uint256 baseRatio = Math.mulDiv(priceLpInPeg, minAssetPriceUsd, priceLoanInUsd);
        return Math.mulDiv(baseRatio, SCALE_FACTOR, 1e18);
    }

    /// @notice Gets the minimum USD price among all pool assets (conservative pricing)
    /// @return minPrice The minimum asset price in USD (8 decimals, Chainlink standard)
    function _getMinimumAssetPrice() internal view returns (uint256) {
        uint256 length = poolAssetFeeds.length;
        uint256 minPrice = type(uint256).max;

        for (uint256 i; i < length; i++) {
            uint256 assetPrice = _fetchFeedPrice(poolAssetFeeds[i], poolAssetHeartbeats[i]);
            if (assetPrice < minPrice) minPrice = assetPrice;
        }

        return minPrice;
    }

    /// @notice Fetches the price from a Chainlink feed.
    /// @param feed The Chainlink feed to fetch the price from.
    /// @param maxStale The maximum number of seconds since the last update of the feed.
    /// @return price The price of the feed, with 18 decimals of precision.
    /// @custom:reverts InvalidPrice if the price fetched from the Chainlink feeds are invalid (negative or 0) or stale.
    function _fetchFeedPrice(IChainlinkFeed feed, uint256 maxStale) internal view returns (uint256) {
        (, int256 latestPrice,, uint256 updatedAt,) = feed.latestRoundData();
        require(latestPrice > 0 && updatedAt > block.timestamp - maxStale, InvalidPrice());
        return uint256(latestPrice);
    }
}

/*───────────────────────────────────────────────────────────────────────────
EXAMPLES – configuring pool asset feeds for conservative pricing
─────────────────────────────────────────────────────────────────────────────
Constructor signature

    CurveStableswapOracle(
        curvePool,
        collateralToken,           // LP token or wrapper
        loanAsset,                 // USDC in the examples below
        loanAssetFeed,             // USDC/USD Chainlink feed
        loanAssetHeartbeat,
        poolAssetFeeds,            // Array of USD feeds for each pool asset
        poolAssetHeartbeats        // Array of heartbeats for each feed
    )

IMPORTANT: The oracle uses MINIMUM pricing among pool assets to prevent
overvaluation during asset depegs. Each pool asset requires a direct USD feed.

---------------------------------------------------------------------
1.  wstETH / wETH  **StableSwap-NG** pool
---------------------------------------------------------------------
• Pool assets: wstETH, wETH
• Both assets are ETH derivatives that can trade at different prices
• Conservative approach: use the lower of the two USD prices

      poolAssetFeeds       = [wstETH/USD feed, wETH/USD feed]
      poolAssetHeartbeats  = [1 days, 1 days]

If wstETH trades at $2,420 and wETH at $2,400, the oracle uses $2,400.

---------------------------------------------------------------------
2.  USDC / USDT  **StableSwap** pool
---------------------------------------------------------------------
• Pool assets: USDC, USDT
• Both are USD stablecoins that can depeg independently
• Conservative approach: use the lower USD price

      poolAssetFeeds       = [USDC/USD feed, USDT/USD feed]
      poolAssetHeartbeats  = [1 days, 1 days]

If USDC = $1.000 and USDT = $0.998, the oracle uses $0.998.

---------------------------------------------------------------------
3.  cbBTC / wBTC  **StableSwap** pool
---------------------------------------------------------------------
• Pool assets: cbBTC, wBTC
• Both are BTC derivatives with potential basis risk
• Conservative approach: prevents overvaluation if cbBTC depegs

      poolAssetFeeds       = [cbBTC/USD feed, wBTC/USD feed]
      poolAssetHeartbeats  = [1 days, 1 days]

If cbBTC = $58,800 and wBTC = $60,000, the oracle uses $58,800.
*/
