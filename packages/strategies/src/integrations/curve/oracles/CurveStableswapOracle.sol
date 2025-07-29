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
 *         Flash-manipulation caveat (single-block virtual_price spikes)
 *         -----------------------------------------------------------
 *         Curve's `get_virtual_price()` is instantaneous: a sufficiently large flash-deposit
 *         and withdrawal can raise the virtual price for a single block.  Because this oracle
 *         reads the value directly without a time-weighted average, protocols integrating it
 *         SHOULD either:
 *           1. apply conservative LLTV, or
 *           2. wrap this oracle in a TWAP layer
 *
 *         The contract is **fully immutable** after deployment: all external parameters are
 *         stored in `immutable` variables and there is no owner or upgrade path.  If the
 *         Chainlink heartbeat assumptions change, a new oracle must be deployed and listed.
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

    /// @notice Address of the Chainlink price feed for the pool's base peg (e.g., ETH/USD).
    /// @dev If the pool's peg is USD, this must be the zero address.
    IChainlinkFeed public immutable BASE_FEED;

    /// @notice Decimals of the base peg's price feed.
    uint8 public immutable BASE_FEED_DECIMALS;

    /// @notice Maximum seconds between two updates of the base peg feed.
    uint256 public immutable BASE_FEED_HEARTBEAT;

    /// @notice Pre-computed factor that scales the oracle output to `ORACLE_BASE_EXPONENT`.
    uint256 public immutable SCALE_FACTOR;

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @dev Thrown when a provided address is the zero address.
    error ZeroAddress();

    /// @dev Thrown when a provided uint256 is zero.
    error ZeroUint256();

    /// @dev Thrown when the Chainlink feed returns a stale or invalid price.
    error InvalidPrice();

    /// @param _curvePool The address of the Curve pool for the LP token collateral.
    /// @param _collateralToken The address of the collateral token of the lending market.
    /// @param _loanAsset The address of the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeed The address of the Chainlink feed for the loan token of the lending market (e.g., USDC/crvUSD).
    /// @param _loanAssetFeedHeartbeat The maximum number of seconds since the last update of the loan asset feed.
    /// @param _baseFeed The address of the Chainlink feed for the pool's underlying peg (e.g., ETH/USD). Pass address(0) if the peg is USD.
    /// @param _baseFeedHeartbeat The maximum number of seconds since the last update of the base feed.
    /// @dev Given a LP/USDC lending market, where LP is the LP token of a Curve Stableswap Pool (or a token strictly pegged to it):
    //       - The `baseFeed` must be Peg/USD where Peg is the unit of account used in the stableswap pool
    //         - If the unit of account of the pool is USD, the given `baseFeed` must be address(0) (e.g., USDC/crvUSD pool)
    //         - If the unit of account of the pool is ETH, the given `baseFeed` must track ETH/USD (e.g., wstETH/wETH pool)
    //         - If the unit of account of the pool is BTC, the given `baseFeed` must track BTC/USD (e.g., wBTC/tBTC pool)
    //       - The `loanAssetFeed` must track the price of the loan asset. In this case, it is USDC/USD. For LP/crvUSD, it would be crvUSD/USD.
    /// @custom:reverts ZeroAddress if `_curvePool`, `_collateralToken`, `_loanAsset`, or `_loanAssetFeed` is the zero address.
    /// @custom:reverts ZeroUint256 if `_loanAssetFeedHeartbeat` is zero.
    /// @custom:reverts ZeroUint256 if `_baseFeedHeartbeat` is zero when `_baseFeed` is provided.
    constructor(
        address _curvePool,
        address _collateralToken,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetFeedHeartbeat,
        address _baseFeed,
        uint256 _baseFeedHeartbeat
    ) {
        require(
            _curvePool != address(0) && _collateralToken != address(0) && _loanAsset != address(0)
                && _loanAssetFeed != address(0),
            ZeroAddress()
        );
        require(_loanAssetFeedHeartbeat > 0, ZeroUint256());
        if (_baseFeed != address(0)) require(_baseFeedHeartbeat > 0, ZeroUint256());

        CURVE_POOL = ICurveStableSwapPool(_curvePool);

        LOAN_ASSET = IERC20Metadata(_loanAsset);
        LOAN_ASSET_FEED = IChainlinkFeed(_loanAssetFeed);
        LOAN_ASSET_FEED_DECIMALS = LOAN_ASSET_FEED.decimals();
        LOAN_ASSET_FEED_HEARTBEAT = _loanAssetFeedHeartbeat;

        // If the "unit of account" of the pool is not USD, we need to use a base feed to convert the "unit of account" to USD.
        if (_baseFeed != address(0)) {
            BASE_FEED = IChainlinkFeed(_baseFeed);
            BASE_FEED_HEARTBEAT = _baseFeedHeartbeat;
            BASE_FEED_DECIMALS = BASE_FEED.decimals();
        } else {
            BASE_FEED = IChainlinkFeed(address(0));
            BASE_FEED_HEARTBEAT = 0;
            // If no base feed is provided, we assume the "unit of account" is USD, so the price is 1.
            // We use 18 decimals as a convention for a normalized price of 1.
            BASE_FEED_DECIMALS = 18;
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
                    - IERC20Metadata(_collateralToken).decimals() - BASE_FEED_DECIMALS
            );
    }

    /// @dev Math.mulDiv rounds toward zero (truncates) so the returned price is lower bound
    ///      It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    ///      10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    ///      decimals of precision.
    /// @return price the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @custom:reverts InvalidPrice if the price fetched from the Chainlink feeds are invalid (negative or 0)
    function price() external view returns (uint256) {
        // 1. Get the price of the LP token in its "unit of account" (e.g., USD for USDC/crvUSD or ETH for wstETH/wETH).
        // This value always has 18 decimals.
        uint256 priceLpInPeg = CURVE_POOL.get_virtual_price();

        // 2. Get the price of the "unit of account" in USD from the base feed.
        uint256 pricePegInUsd;
        if (address(BASE_FEED) != address(0)) {
            pricePegInUsd = _fetchFeedPrice(BASE_FEED, BASE_FEED_HEARTBEAT);
        } else {
            // If no base feed, "unit of account" is USD. The price is 1, represented with `BASE_FEED_DECIMALS` (18) precision.
            pricePegInUsd = 10 ** uint256(BASE_FEED_DECIMALS);
        }

        // 3. Get the price of the loan asset in USD from its Chainlink feed.
        uint256 priceLoanInUsd = _fetchFeedPrice(LOAN_ASSET_FEED, LOAN_ASSET_FEED_HEARTBEAT);

        // 4. Aggregate and scale to 1e36 using the pre-computed SCALE_FACTOR.
        // Formula: price(LP/Loan) = (priceLpInPeg * pricePegInUsd / priceLoanInUsd) * SCALE_FACTOR
        uint256 baseRatio = Math.mulDiv(priceLpInPeg, pricePegInUsd, priceLoanInUsd);
        return Math.mulDiv(baseRatio, SCALE_FACTOR, 1e18);
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
EXAMPLES – choosing the `baseFeed` parameter
─────────────────────────────────────────────────────────────────────────────
Constructor signature

    CurveStableswapOracle(
        curvePool,
        loanAsset,                 // USDC in the examples below
        loanAssetFeed,             // USDC/USD Chainlink feed
        loanAssetHeartbeat,
        baseFeed,                  // Peg/USD feed (or address(0) if peg = USD)
        baseFeedHeartbeat
    )

---------------------------------------------------------------------
1.  weETH / wETH  **StableSwap-NG** pool (token0 = wETH)
---------------------------------------------------------------------
• Unit-of-account (peg) = **ETH**.
• You must supply a live **ETH/USD** Chainlink feed so that the oracle can
  convert the LP's ETH-denominated `get_virtual_price()` into USD.

      baseFeed             = ETH/USD feed
      baseFeedHeartbeat    = 1 days      // whatever the feed docs specify

The loan-asset parameters remain the same as usual (USDC + USDC/USD feed).

---------------------------------------------------------------------
2.  Curve.fi Strategic USD Reserves  pool (USDC / USDT) (token0 = USDC)
---------------------------------------------------------------------
• Unit-of-account = **USD** (all constituents are USD-pegged stables).
• Set `baseFeed = address(0)` to tell the oracle that 1 peg-unit = 1 USD.

      baseFeed             = address(0)  // no conversion needed
      baseFeedHeartbeat    = 0           // ignored when baseFeed is zero

With `baseFeed` omitted, the formula collapses to

    Price(LP / USDC) = get_virtual_price() / (USDC/USD)

which automatically reflects any USDC de-peg while avoiding an unnecessary
feed call.
*/
