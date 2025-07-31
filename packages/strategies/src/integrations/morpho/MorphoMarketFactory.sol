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
    /// @param initialLoanSupply The initial amount of loan token to seed the market with
    /// @return id The identifier of the freshly created market
    /// @custom:throws InvalidLLTV if the LLTV is invalid
    /// @custom:throws InvalidIRM if the IRM is invalid
    function create(
        IStrategyWrapper collateral,
        IERC20Metadata loan,
        IOracle oracle,
        address irm,
        uint256 lltv,
        uint256 initialLoanSupply
    ) external onlyDelegateCall returns (Id id) {
        require(MORPHO_BLUE.isLltvEnabled(lltv), InvalidLLTV());
        require(MORPHO_BLUE.isIrmEnabled(irm), InvalidIRM());

        // 1. Create the Morpho Blue market
        MarketParams memory morphoMarketParams = MarketParams({
            loanToken: address(loan),
            collateralToken: address(collateral),
            oracle: address(oracle),
            irm: irm,
            lltv: lltv
        });
        id = MarketParamsLib.id(morphoMarketParams);
        // prevent a DoS attack that would prevent us for deploying the market
        if (MORPHO_BLUE.market(id).lastUpdate == 0) MORPHO_BLUE.createMarket(morphoMarketParams);

        // 2. Initialize the collateral by setting the approved market ID
        collateral.initialize(Id.unwrap(id));

        emit MarketDeployed(address(MORPHO_BLUE), address(collateral), address(loan), address(oracle), lltv, irm);

        // 3. Pre-seed the market if needed
        if (initialLoanSupply != 0) _preSeedMarket(initialLoanSupply, morphoMarketParams);
    }

    /// @notice Pre-seeds the market with the given amount of loan token
    /// @dev Prevent Zero Utilization Rate Decay at Deployment by supplying and borrowing
    function _preSeedMarket(uint256 initialLoanSupply, MarketParams memory morphoMarketParams) internal {
        // Provide initial loan token liquidity to the freshly created market
        IERC20Metadata(morphoMarketParams.loanToken).safeTransferFrom(msg.sender, address(this), initialLoanSupply);
        IERC20Metadata(morphoMarketParams.loanToken).forceApprove(address(MORPHO_BLUE), initialLoanSupply);
        MORPHO_BLUE.supply({
            marketParams: morphoMarketParams,
            assets: initialLoanSupply,
            shares: 0,
            onBehalf: msg.sender,
            data: hex""
        });

        // Provide initial collateral to the market
        uint256 borrowAmount = (initialLoanSupply * 9) / 10; // 90% of supplied liquidity
        uint256 collateralToSupply = Math.mulDiv(
            Math.mulDiv(
                borrowAmount,
                10 ** IOracle(morphoMarketParams.oracle).ORACLE_BASE_EXPONENT(),
                IOracle(morphoMarketParams.oracle).price(),
                Math.Rounding.Ceil
            ),
            1e18,
            Math.mulDiv(morphoMarketParams.lltv, 9_500, 10_000), // 95 % of LLTV
            Math.Rounding.Ceil
        );

        IRewardVault vault = IStrategyWrapper(morphoMarketParams.collateralToken).REWARD_VAULT();
        vault.safeTransferFrom(msg.sender, address(this), collateralToSupply);
        vault.approve(morphoMarketParams.collateralToken, collateralToSupply);

        // Bootstrap utilisation: post enough collateral to reach 95 % of LLTV
        IStrategyWrapper(morphoMarketParams.collateralToken).depositShares(collateralToSupply);

        // Bootstrap utilisation: borrow 90 % of that
        MORPHO_BLUE.borrow({
            marketParams: morphoMarketParams,
            assets: borrowAmount,
            shares: 0,
            onBehalf: address(this),
            receiver: msg.sender
        });

        // Authorize the caller to manage the position
        MORPHO_BLUE.setAuthorization(msg.sender, true);
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
