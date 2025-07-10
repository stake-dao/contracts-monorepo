// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Id} from "shared/src/morpho/IMorpho.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {ILendingFactory} from "src/interfaces/ILendingFactory.sol";
import {MarketParamsLib} from "shared/src/morpho/MarketParamsLib.sol";

/// @title Morpho Market Factory
/// @notice Factory that creates Stake DAO markets on Morpho Blue
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract MorphoMarketFactory is ILendingFactory {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IRewardVault;

    /// @dev The address of the lending protocol
    IMorpho private immutable MORPHO_BLUE;

    /// @dev The address of this contract
    ///      Used to check if the `create` function is called with a delegate call
    address private immutable THIS;

    ///////////////////////////////////////////////////////////////
    // --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @dev Emitted when a market is deployed. This is an anonymous event (!)
    event MarketDeployed(
        address indexed protocol,
        address indexed collateral,
        address indexed loan,
        address indexed oracle,
        uint256 lltv,
        address irm
    ) anonymous;

    /// @dev Thrown when the given address is zero.
    error AddressZero();

    /// @dev Thrown when the LLTV is invalid.
    error InvalidLLTV();

    /// @dev Thrown when the IRM is invalid
    error InvalidIRM();

    /// @dev Thrown when the factory is not authorized to supply/borrow on behalf of the caller.
    error InvalidAuthorized();

    /// @dev Thrown when the factory is not called with a delegate call.
    error DelegateCallOnly();

    /// @param _morphoBlue The address of the lending protocol where the markets will be created
    constructor(address _morphoBlue) {
        require(_morphoBlue != address(0), AddressZero());
        MORPHO_BLUE = IMorpho(_morphoBlue);
        THIS = address(this);
    }

    /// @custom:throws DelegateCallOnly if the `create` function is not called with a delegate call
    modifier onlyDelegateCall() {
        require(address(this) != THIS, DelegateCallOnly());
        _;
    }

    ///////////////////////////////////////////////////////////////
    // --- MARKET CREATION
    ///////////////////////////////////////////////////////////////

    /// @notice Creates a Morpho market for a given collateral, loan, oracle, IRM and LLTV
    /// @param collateral The collateral token
    /// @param loan The loan token
    /// @param oracle The oracle to use for the market
    /// @param irm The Interest Rate Model
    /// @param lltv The Liquidation Loan-To-Value
    /// @return id The identifier of the freshly created market
    /// @custom:throws InvalidLLTV if the LLTV is invalid
    /// @custom:throws InvalidIRM if the IRM is invalid
    /// @custom:throws InvalidAuthorized if this is not authorized to supply/borrow on behalf of the caller
    function create(IStrategyWrapper collateral, IERC20Metadata loan, IOracle oracle, address irm, uint256 lltv)
        external
        onlyDelegateCall
        returns (Id id)
    {
        require(MORPHO_BLUE.isLltvEnabled(lltv), InvalidLLTV());
        require(MORPHO_BLUE.isIrmEnabled(irm), InvalidIRM());
        require(MORPHO_BLUE.isAuthorized(msg.sender, address(this)), InvalidAuthorized());

        // 1. Create the Morpho Blue market
        MarketParams memory morphoMarketParams = MarketParams({
            loanToken: address(loan),
            collateralToken: address(collateral),
            oracle: address(oracle),
            irm: irm,
            lltv: lltv
        });
        MORPHO_BLUE.createMarket(morphoMarketParams);

        // 2. Prevent Zero Utilization Rate Decay at Deployment by supplying and borrowing
        // https://docs.morpho.org/curation/tutorials/creating-market#fill-all-attributes

        // ------------------------------------------------------------------
        // Provide initial loan token liquidity to the freshly created market
        // ------------------------------------------------------------------

        // Feed the market with exactly 1 token so that there is available liquidity for the subsequent borrow.
        uint256 loanToSupply = 10 ** loan.decimals();
        loan.safeTransferFrom(msg.sender, address(this), loanToSupply);
        loan.approve(address(MORPHO_BLUE), loanToSupply);
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
        // maxBorrow = collateral * price / ORACLE_BASE_EXPONENT * LLTV
        //           ⇒ collateral = borrowAmount * ORACLE_BASE_EXPONENT / price / LLTV
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
            Math.mulDiv(borrowAmount, 10 ** oracle.ORACLE_BASE_EXPONENT(), oracle.price(), Math.Rounding.Ceil),
            1e18,
            lltv,
            Math.Rounding.Ceil
        );
        uint256 buffer = 2 * (10 ** (collateral.decimals() - loan.decimals()));
        collateralToSupply += buffer; // guarantees health-check passes

        // Transfer the shares of the vault and deposit them into the strategy wrapper
        // before supplying the given collateral to Morpho.
        IRewardVault vault = collateral.REWARD_VAULT();
        vault.safeTransferFrom(msg.sender, address(this), collateralToSupply);
        vault.approve(address(collateral), collateralToSupply);
        collateral.depositShares(collateralToSupply);
        collateral.approve(address(MORPHO_BLUE), collateralToSupply);
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
        emit MarketDeployed(address(MORPHO_BLUE), address(collateral), address(loan), address(oracle), lltv, irm);

        id = MarketParamsLib.id(morphoMarketParams);
    }

    ///////////////////////////////////////////////////////////////
    // GETTERS
    ///////////////////////////////////////////////////////////////

    /// @return protocol The address of the Morpho Blue protocol.
    function protocol() external view returns (address) {
        return address(MORPHO_BLUE);
    }

    /// @return version The version of the factory.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @return _ The identifier of the factory.
    function identifier() external pure returns (string memory) {
        return type(MorphoMarketFactory).name;
    }
}
