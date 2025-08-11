// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurveCryptoSwapPool} from "src/interfaces/ICurvePool.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

/**
 * @title  CurveCryptoswapOracle
 * @notice Read-only price oracle that returns the value of one Curve
 *          **Crypto-swap** LP token expressed in an arbitrary **loan
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
 *           by hop, convert *token0* into USD. Each element consumes the output
 *           of the previous hop.
 *
 *         If needed, each element of `token0ToUsdFeeds` **must be** a compatible
 *         Chainlink price feed.
 *
 *         Flash-manipulation caveat
 *         -------------------------------------------
 *         This oracle implements conservative minimum pricing across all pool assets
 *         and is intended for high-TVL, curated pools only. While `get_virtual_price()`
 *         could theoretically be manipulated, the multi-layer protections and economic
 *         barriers make such attacks practically infeasible for the target deployment.
 *         Conservative LLTV settings are still recommended for additional safety.
 *
 *         Limitations – Layer 2 sequencer availability
 *         -------------------------------------------
 *         This oracle lacks sequencer uptime validation for Layer 2 networks. Chainlink
 *         feeds on L2s can become stale if the sequencer goes down. For L2 deployments,
 *         consider wrapping this oracle to include Sequencer Uptime Data Feed checks.
 *         https://docs.chain.link/data-feeds/l2-sequencer-feeds
 */
contract CurveCryptoswapOracle is IOracle {
    ///////////////////////////////////////////////////////////////
    // --- IMMUTABLES & STORAGE
    ///////////////////////////////////////////////////////////////

    /// @notice Scale factor for the oracle price.
    uint256 public constant ORACLE_BASE_EXPONENT = 36;

    // Crypto-swap pool (including TwoCrypto-NG pool)
    ICurveCryptoSwapPool public immutable CURVE_POOL;

    // LoanAsset/USD feed (e.g., USDC/USD, crvUSD/USD, USDT/USD, etc.)
    IERC20Metadata public immutable LOAN_ASSET;
    IChainlinkFeed public immutable LOAN_ASSET_FEED;
    uint8 public immutable LOAN_ASSET_FEED_DECIMALS;
    uint256 public immutable LOAN_ASSET_FEED_HEARTBEAT;

    // Feeds that turn token0 into USD (ordered hops). Stored in arrays as their count is pool-specific.
    IChainlinkFeed[] public token0ToUsdFeeds;
    uint256[] public token0ToUsdHeartbeats;

    // ---------------------------------------------------------------------
    // SCALE FACTOR
    // ---------------------------------------------------------------------
    // Lending protocols such as Morpho Blue require oracle prices to be scaled
    // by `ORACLE_BASE_EXPONENT` and adjusted for the difference in token decimals between
    // the loan asset (debt unit) and the collateral asset (wrapped Curve LP token).
    //
    // The raw price we compute below (named `basePrice`) returns the value
    // of **1 LP token** expressed in **1 unit of the loan asset** with
    // 18 decimals of precision (WAD). To rescale it to the format expected
    // by the lending protocol we must multiply by:
    //   10^(`ORACLE_BASE_EXPONENT` + loanDecimals − collateralDecimals)
    //
    // As with the StableSwap oracle, this exponent is guaranteed to be
    // non-negative for the LP tokens we target, therefore the factor fits
    // in a `uint256` and can be pre-computed once in the constructor.
    // ---------------------------------------------------------------------
    uint256 public immutable SCALE_FACTOR;

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    error ZeroAddress();
    error ZeroUint256();
    error ArrayLengthMismatch();
    error InvalidPrice();

    ///////////////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @param _curvePool Address of the Crypto-swap pool.
    /// @param _collateralToken Address of the collateral token.
    /// @param _loanAsset Address of the loan asset.
    /// @param _loanAssetFeed Chainlink feed for the loan asset if needed (e.g., USDC/USD, crvUSD/USD, USDT/USD, etc.).
    /// @param _loanAssetHeartbeat Max seconds between two updates of the loan asset feed.
    /// @param _token0ToUsdFeeds Ordered feeds to convert token0 to USD.
    /// @param _token0ToUsdHeartbeats Max seconds between two updates of each feed.
    /// @custom:reverts ZeroAddress if `_curvePool`, `_collateralToken`, `_loanAsset` is the zero address.
    /// @custom:reverts ZeroUint256 if `_loanAssetHeartbeat` is zero.
    /// @custom:reverts ArrayLengthMismatch if `_token0ToUsdFeeds` and `_token0ToUsdHeartbeats` have different lengths.
    /// @dev If `_loanAssetFeed` is the zero address, it means that the loan asset is the coins0 of the pool.
    ///      In this case, there is no need to set up the loan asset feed data (_loanAssetFeed, _loanAssetFeedDecimals, _loanAssetFeedHeartbeat).
    constructor(
        address _curvePool,
        address _collateralToken,
        address _loanAsset,
        address _loanAssetFeed,
        uint256 _loanAssetHeartbeat,
        address[] memory _token0ToUsdFeeds,
        uint256[] memory _token0ToUsdHeartbeats
    ) {
        if (_curvePool == address(0)) revert ZeroAddress();
        if (_collateralToken == address(0)) revert ZeroAddress();
        if (_loanAsset == address(0)) revert ZeroAddress();
        if (_token0ToUsdFeeds.length != _token0ToUsdHeartbeats.length) revert ArrayLengthMismatch();

        CURVE_POOL = ICurveCryptoSwapPool(_curvePool);
        LOAN_ASSET = IERC20Metadata(_loanAsset);
        SCALE_FACTOR = 10
            ** (ORACLE_BASE_EXPONENT + IERC20Metadata(_loanAsset).decimals() - IERC20Metadata(_collateralToken).decimals());

        // Set the loan asset feed data if needed
        bool isCoin0LoanAsset = (_loanAssetFeed == address(0) && _loanAssetHeartbeat == 0);
        if (isCoin0LoanAsset) {
            // Validate that coin0 actually equals loan asset. If so, we can avoid setting up the loan asset feed data
            require(ICurveCryptoSwapPool(_curvePool).coins(0) == _loanAsset, "Loan asset must be token0");
        } else {
            // Set up feeds for conversion case
            require(_loanAssetFeed != address(0), ZeroAddress());
            require(_loanAssetHeartbeat != 0, ZeroUint256());
            LOAN_ASSET_FEED = IChainlinkFeed(_loanAssetFeed);
            LOAN_ASSET_FEED_DECIMALS = IChainlinkFeed(_loanAssetFeed).decimals();
            LOAN_ASSET_FEED_HEARTBEAT = _loanAssetHeartbeat;
        }

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
        // Step 1: fetch the price of the LP token denominated in token0 (1e18 decimals)
        uint256 lpInToken0 = CURVE_POOL.lp_price();
        // Step 1.b: If there is no loan asset feed, it means coisn0 equals loan asset, so we can scale the returned price directly
        if (LOAN_ASSET_FEED == IChainlinkFeed(address(0))) return _scalePrice(lpInToken0);

        // Step 2: convert token0 to USD via the feed chain (1e18 scale)
        uint256 token0Usd = 10 ** 18;
        uint256 length = token0ToUsdFeeds.length;
        for (uint256 i; i < length; i++) {
            IChainlinkFeed feed = token0ToUsdFeeds[i];
            uint256 feedPrice = _fetchFeedPrice(feed, token0ToUsdHeartbeats[i]);
            uint8 feedDecimals = feed.decimals();
            token0Usd = Math.mulDiv(token0Usd, feedPrice, 10 ** feedDecimals);
        }

        // Step 3: loan asset price.
        uint256 loanAssetUsd = _fetchFeedPrice(LOAN_ASSET_FEED, LOAN_ASSET_FEED_HEARTBEAT);

        // Step 4: lp_price * token0/USD / (loan asset/USD) (still 18 decimals)
        uint256 lpUsd = Math.mulDiv(lpInToken0, token0Usd, 10 ** 18);

        // Base price scaled to 18 decimals (LP / Loan)
        uint256 basePrice = Math.mulDiv(lpUsd, 10 ** LOAN_ASSET_FEED_DECIMALS, loanAssetUsd);
        //      (18 decimals)            └─ 18-dec  · 10^loanFeedDec  /  loanAssetUsd(loanFeedDec)

        // Scale to 1e36 and adjust for token-decimal difference
        return _scalePrice(basePrice);
    }

    /// @notice Fetches the price from a Chainlink feed
    /// @param feed The Chainlink feed to fetch the price from.
    /// @param maxStale The maximum number of seconds since the last update of the feed.
    /// @return price The price of the feed, with 18 decimals of precision.
    /// @custom:reverts InvalidPrice if the price fetched from the Chainlink feeds are invalid (not positive) or stale.
    function _fetchFeedPrice(IChainlinkFeed feed, uint256 maxStale) internal view returns (uint256) {
        (, int256 latestPrice,, uint256 updatedAt,) = feed.latestRoundData();
        require(latestPrice > 0 && updatedAt > block.timestamp - maxStale, InvalidPrice());
        return uint256(latestPrice);
    }

    /// @notice Scales the price according to the scale factor
    /// @param unscaledPrice The price to scale.
    function _scalePrice(uint256 unscaledPrice) internal view returns (uint256) {
        return Math.mulDiv(unscaledPrice, SCALE_FACTOR, 1e18);
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

---------------------------------------------------------------------
1.  TriCrypto-USDT pool  (USDT / wBTC / WETH)   → token0 = USDT
---------------------------------------------------------------------
• Goal: LP / USDC price.
• Risk: USDT can de-peg from the dollar.

Constructor parameters:

    token0ToUsdFeeds       = [ USDT/USD feed ]
    token0ToUsdHeartbeats  = [ 1 days ]            // whatever defined by the chainlink feed
    loanAssetFeed          = USDC/USD feed

The USDT/USD feed is mandatory so the oracle reacts to any USDT de-peg.

---------------------------------------------------------------------
2.  TriCrypto-USDC pool  → token0 = USDC
---------------------------------------------------------------------
Because *token0* equals the **loan asset** (USDC), there is no need to set up
the token0ToUsdFeeds parameters as well as the loanAssetFeed parameters.
In this case, the Curve pool already returns the price of the LP token in the loan asset.

      token0ToUsdFeeds       = [ ]
      token0ToUsdHeartbeats  = [ ]
      loanAssetFeed          = address(0)

The oracle fetch the price of the LP token in the loan asset directly from the pool
and scale it to the expected scaling factor.

---------------------------------------------------------------------
3.  WETH / RSUP pool  → token0 = wETH
---------------------------------------------------------------------
• WETH is a **1:1 non-rebasing wrapper** around ETH.
• Because WETH unwraps 1:1 into ETH, you **omit** that hop and use the
  ETH/USD feed directly.

Constructor parameters:

    token0ToUsdFeeds       = [ ETH/USD feed ]
    token0ToUsdHeartbeats  = [ 1 days       ]   // heartbeat defined by the feed
    loanAssetFeed          = USDC/USD feed

Because WETH unwraps 1:1 into ETH, the single ETH/USD feed already converts
token0 (WETH) into USD. Finally, the contract divides by the USDC/USD feed
(passed as `loanAssetFeed`) to obtain LP / USDC.
*/
