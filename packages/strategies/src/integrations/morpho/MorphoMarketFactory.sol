// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams} from "shared/src/morpho/IMorpho.sol";
import {CurveStableswapOracle} from "src/integrations/curve/oracles/CurveStableswapOracle.sol";
import {CurveCryptoswapOracle} from "src/integrations/curve/oracles/CurveCryptoswapOracle.sol";
import {RestrictedStrategyWrapper} from "src/wrappers/RestrictedStrategyWrapper.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Morpho Market Factory
/// @notice Factory for creating Morpho markets for a given reward vault linked to a Curve pool.
/// @dev   - Allows users to create Morpho markets for a given reward vault linked to a Curve pool.
///        - Uses a stableswap oracle to price the collateral token.
///        - Uses a cryptoswap oracle to price the collateral token.
///        - Uses a RestrictedStrategyWrapper to wrap the reward vault shares.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract MorphoMarketFactory is Ownable2Step {
    using SafeERC20 for IERC20;
    using SafeERC20 for IRewardVault;

    IMorpho public immutable MORPHO_BLUE;
    IProtocolController public immutable PROTOCOL_CONTROLLER;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    ///////////////////////////////////////////////////////////////
    // --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    event MarketDeployed(
        address indexed loanAsset, address indexed collateralAsset, address oracle, uint256 indexed lltv, address irm
    );

    /// @dev Thrown when the given address is zero.
    error AddressZero();

    /// @dev Thrown when the LLTV is invalid.
    error InvalidLLTV();

    /// @dev Thrown when the IRM is invali
    error InvalidIRM();

    /// @dev Thrown when the factory is not authorized to supply/borrow on behalf of the caller.
    error InvalidAuthorized();

    /// @dev Thrown when the reward vault is not registered in the protocol controller.
    error InvalidRewardVault();

    /// @dev Thrown when the caller does not have enough allowance to supply the collateral.
    error NotEnoughCollateralAllowed(uint256 required);

    /// @dev Thrown when the caller does not have enough allowance to supply the loan asset.
    error NotEnoughLoanAssetAllowed(uint256 required);

    /// @dev The parameters for creating a Morpho stableswap oracle.
    struct StableswapOracleParams {
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address baseFeed;
        uint256 baseFeedHeartbeat;
    }

    /// @dev The parameters for creating a Morpho cryptoswap oracle.
    struct CryptoswapOracleParams {
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address[] token0ToUsdFeeds;
        uint256[] token0ToUsdHeartbeats;
    }

    /// @dev The parameters for creating a Morpho market.
    ///      Both the IRM and the LLTV must be valid values pre-approved by Morpho.
    struct MorphoMarketParams {
        address loanAsset;
        /// The Interest Rate Model that must be enabled for the market
        address irm;
        /// The pre-approved Liquidation Loan-To-Value
        uint256 lltv;
    }

    constructor(address _morphoBlue, address _protocolController) Ownable(msg.sender) {
        require(_morphoBlue != address(0) && _protocolController != address(0), AddressZero());

        MORPHO_BLUE = IMorpho(_morphoBlue);
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
    }

    ///////////////////////////////////////////////////////////////
    // --- EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Creates a Morpho market for a given reward vault and market parameters using a stableswap oracle
    /// @param rewardVault The reward vault to use for the market
    /// @param oracleParams The parameters for the stableswap oracle
    /// @param marketParams The parameters for the market
    function createStableswapMarket(
        IRewardVault rewardVault,
        StableswapOracleParams calldata oracleParams,
        MorphoMarketParams calldata marketParams
    )
        external
        onlyOwner
        verifyParams(rewardVault, marketParams)
        returns (MarketParams memory morphoMarketParams, IOracle oracle, IStrategyWrapper wrapper)
    {
        // 1. Deploy the token that wraps the reward vault for Morpho Blue compatibility
        wrapper = new RestrictedStrategyWrapper(rewardVault, address(MORPHO_BLUE));

        // 2. Deploy the oracle
        oracle = new CurveStableswapOracle(
            rewardVault.asset(), // The curve pool associated with the reward vault
            address(wrapper),
            marketParams.loanAsset,
            oracleParams.loanAssetFeed,
            oracleParams.loanAssetFeedHeartbeat,
            oracleParams.baseFeed,
            oracleParams.baseFeedHeartbeat
        );

        // 3. Deploy and setup the Morpho Market
        morphoMarketParams = _deployMorphoMarket(rewardVault, marketParams, wrapper, oracle);
    }

    /// @notice Creates a Morpho market for a given reward vault and market parameters using a cryptoswap oracle
    /// @param rewardVault The reward vault to use for the market
    /// @param oracleParams The parameters for the cryptoswap oracle
    /// @param marketParams The parameters for the market
    function createCryptoswapMarket(
        IRewardVault rewardVault,
        CryptoswapOracleParams calldata oracleParams,
        MorphoMarketParams calldata marketParams
    )
        external
        onlyOwner
        verifyParams(rewardVault, marketParams)
        returns (MarketParams memory morphoMarketParams, IOracle oracle, IStrategyWrapper wrapper)
    {
        // 1. Deploy the token that wraps the reward vault for Morpho Blue compatibility
        wrapper = new RestrictedStrategyWrapper(rewardVault, address(MORPHO_BLUE));

        // 2. Deploy the oracle
        oracle = new CurveCryptoswapOracle(
            rewardVault.asset(), // The curve pool associated with the reward vault
            address(wrapper),
            marketParams.loanAsset,
            oracleParams.loanAssetFeed,
            oracleParams.loanAssetFeedHeartbeat,
            oracleParams.token0ToUsdFeeds,
            oracleParams.token0ToUsdHeartbeats
        );

        // 2. Deploy and setup the Morpho Market
        morphoMarketParams = _deployMorphoMarket(rewardVault, marketParams, wrapper, oracle);
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    modifier verifyParams(IRewardVault rewardVault, MorphoMarketParams calldata marketParams) {
        require(MORPHO_BLUE.isLltvEnabled(marketParams.lltv), InvalidLLTV());
        require(MORPHO_BLUE.isIrmEnabled(marketParams.irm), InvalidIRM());
        require(MORPHO_BLUE.isAuthorized(msg.sender, address(this)), InvalidAuthorized());
        require(PROTOCOL_CONTROLLER.vaults(rewardVault.gauge()) == address(rewardVault), InvalidRewardVault());

        _;
    }

    function _deployMorphoMarket(
        IRewardVault rewardVault,
        MorphoMarketParams calldata marketParams,
        IStrategyWrapper wrapper,
        IOracle oracle
    ) internal returns (MarketParams memory morphoMarketParams) {
        // 1. Create the Morpho Blue market
        morphoMarketParams = MarketParams({
            loanToken: marketParams.loanAsset,
            collateralToken: address(wrapper),
            oracle: address(oracle),
            irm: marketParams.irm,
            lltv: marketParams.lltv
        });
        MORPHO_BLUE.createMarket(morphoMarketParams);

        // 2. Prevent Zero Utilization Rate Decay at Deployment by supplying and borrowing
        // https://docs.morpho.org/curation/tutorials/creating-market#fill-all-attributes

        // ------------------------------------------------------------------
        // Provide initial loan token liquidity to the freshly created market
        // ------------------------------------------------------------------

        // Feed the market with exactly 1 token so that there is available liquidity for the subsequent borrow.
        uint256 loanToSupply = 10 ** IERC20Metadata(marketParams.loanAsset).decimals();
        IERC20(marketParams.loanAsset).safeTransferFrom(msg.sender, address(this), loanToSupply);
        IERC20(marketParams.loanAsset).approve(address(MORPHO_BLUE), loanToSupply);
        MORPHO_BLUE.supply({
            marketParams: morphoMarketParams,
            assets: loanToSupply,
            shares: 0,
            onBehalf: msg.sender,
            data: hex""
        });

        // Supply the collateral token to Morpho. Just enough to allow borrowing 90% of the supplied loan asset.
        uint256 borrowAmount = (loanToSupply * 9) / 10; // 90% of supplied liquidity

        // ------------------------------------------------------------------
        // Determine the minimal amount of collateral (LP tokens) required so
        // that the position remains healthy right after borrowing
        //
        // maxBorrow = collateral * price / 1e36 * LLTV
        //           ⇒ collateral = borrowAmount * 1e36 / price / LLTV
        //
        // # Add deterministic buffer: 2 loan-wei expressed in LP-wei
        //
        // Morpho Blue's health-check can discard at most TWO loan-wei of value
        // because of the successive "round-down" operations it performs.
        // If we are short by ≥ 2 loan-wei the position may be flagged as
        // unhealthy.  To make the deployment fully deterministic we therefore
        // add exactly two smallest units of the *loan* token, converted into
        // collateral units.
        //
        // loan-wei → LP-wei conversion: 1 loan-wei corresponds to
        // 10^(collDec-loanDec) wei of the collateral token (because the oracle
        // scales with 10^(loanDec-collDec)).  Multiplying that by 2 gives the
        // minimal amount that always offsets the worst-case rounding loss,
        // while remaining economically negligible (≈ 0.005 USDC for a ETH/USDC for example).
        // ------------------------------------------------------------------
        uint256 collateralToSupply = Math.mulDiv(
            Math.mulDiv(borrowAmount, ORACLE_PRICE_SCALE, IOracle(address(oracle)).price(), Math.Rounding.Ceil),
            1e18,
            marketParams.lltv,
            Math.Rounding.Ceil
        );
        uint256 buffer = 2 * (10 ** (wrapper.decimals() - IERC20Metadata(marketParams.loanAsset).decimals()));
        collateralToSupply += buffer; // guarantees health-check passes

        // Transfer the LP tokens from the caller and wrap
        rewardVault.safeTransferFrom(msg.sender, address(this), collateralToSupply);
        rewardVault.approve(address(wrapper), collateralToSupply);
        wrapper.depositShares(collateralToSupply);
        wrapper.approve(address(MORPHO_BLUE), collateralToSupply);
        MORPHO_BLUE.supplyCollateral({
            marketParams: morphoMarketParams,
            assets: collateralToSupply,
            onBehalf: msg.sender,
            data: hex""
        });

        // Borrow 90 % of the supplied loan asset back to put the utilization rate in the expected range.
        // This loan is covered by the collateral supplied before.
        MORPHO_BLUE.borrow({
            marketParams: morphoMarketParams,
            assets: borrowAmount,
            shares: 0,
            onBehalf: msg.sender,
            receiver: msg.sender
        });

        // 3. Trigger the deployment event
        emit MarketDeployed(
            marketParams.loanAsset, address(wrapper), address(oracle), marketParams.lltv, marketParams.irm
        );
    }

    /// @return version The version of the factory.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function identifier() external pure returns (string memory) {
        return type(MorphoMarketFactory).name;
    }
}
