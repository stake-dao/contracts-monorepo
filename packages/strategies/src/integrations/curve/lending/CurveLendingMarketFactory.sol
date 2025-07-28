// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {CurveStableswapOracle} from "src/integrations/curve/oracles/CurveStableswapOracle.sol";
import {CurveCryptoswapOracle} from "src/integrations/curve/oracles/CurveCryptoswapOracle.sol";
import {RestrictedStrategyWrapper} from "src/wrappers/RestrictedStrategyWrapper.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {ILendingFactory} from "src/interfaces/ILendingFactory.sol";
import {IMetaRegistry} from "@interfaces/curve/IMetaRegistry.sol";

/// @title Curve Lending Market Factory
/// @notice Creates a lending market for Curve-associated Stake DAO reward vaults on the given lending protocol
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract CurveLendingMarketFactory is Ownable2Step {
    /// @dev The address of the Stake DAO Staking v2 protocol controller
    ///      Used to check if the reward vault is genuine
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @dev The address of the Curve meta registry
    IMetaRegistry public immutable META_REGISTRY;

    ///////////////////////////////////////////////////////////////
    // --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    event CollateralDeployed(address collateral);
    event OracleDeployed(address oracle);

    /// @dev Thrown when the given address is zero.
    error AddressZero();

    /// @dev Thrown when the reward vault is not registered in the protocol controller.
    error InvalidRewardVault();

    /// @dev Thrown when the reward vault is not a Curve reward vault.
    error InvalidProtocolId();

    /// @dev Thrown when the delegate call fails.
    error MarketCreationFailed();

    /// @dev The parameters for creating a Curve stableswap oracle.
    struct StableswapOracleParams {
        address loanAsset;
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address baseFeed;
        uint256 baseFeedHeartbeat;
    }

    /// @dev The parameters for creating a Curve cryptoswap oracle.
    struct CryptoswapOracleParams {
        address loanAsset;
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address[] token0ToUsdFeeds;
        uint256[] token0ToUsdHeartbeats;
    }

    /// @dev The parameters needed for the market creation
    ///      Both the IRM and the LLTV must be valid values pre-approved by the lending protocol.
    struct MarketParams {
        /// The Interest Rate Model that must be enabled for the market
        address irm;
        /// The pre-approved Liquidation Loan-To-Value
        uint256 lltv;
        /// The initial amount of collateral to supply to the market
        uint256 initialSupply;
    }

    constructor(address _protocolController, address _metaRegistry) Ownable(msg.sender) {
        require(_protocolController != address(0), AddressZero());
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
        META_REGISTRY = IMetaRegistry(_metaRegistry);
    }

    modifier isValidDeployment(IRewardVault rewardVault) {
        require(PROTOCOL_CONTROLLER.vaults(rewardVault.gauge()) == address(rewardVault), InvalidRewardVault());
        require(rewardVault.PROTOCOL_ID() == bytes4(keccak256("CURVE")), InvalidProtocolId());
        _;
    }

    ///////////////////////////////////////////////////////////////
    // --- MARKET CREATION
    ///////////////////////////////////////////////////////////////

    /// @notice Creates a Stake DAO market on Curve using a stableswap oracle
    /// @dev The lending factory must be trusted!
    ///      The ownership of this contract is propagated to the lending factory
    /// @param rewardVault The reward vault to use for the market
    /// @param oracleParams The parameters for the stableswap oracle
    /// @param marketParams The parameters for the market
    /// @param lendingFactory The factory to use for the market
    /// @return collateral The wrapper for the collateral token
    /// @return oracle The oracle for the market
    /// @return data The data returned by the lending factory
    function deploy(
        IRewardVault rewardVault,
        StableswapOracleParams calldata oracleParams,
        MarketParams calldata marketParams,
        ILendingFactory lendingFactory
    ) external onlyOwner isValidDeployment(rewardVault) returns (IStrategyWrapper, IOracle, bytes memory) {
        // 1. Deploy the collateral token
        IStrategyWrapper collateral = _deployCollateral(rewardVault, lendingFactory);

        // 2. Deploy the oracle
        IOracle oracle = new CurveStableswapOracle(
            META_REGISTRY.get_pool_from_lp_token(rewardVault.asset()),
            address(collateral),
            oracleParams.loanAsset,
            oracleParams.loanAssetFeed,
            oracleParams.loanAssetFeedHeartbeat,
            oracleParams.baseFeed,
            oracleParams.baseFeedHeartbeat
        );
        emit OracleDeployed(address(oracle));

        // 3. Create the lending market
        bytes memory data = _createMarket(collateral, oracle, oracleParams.loanAsset, lendingFactory, marketParams);
        return (collateral, oracle, data);
    }

    /// @notice Creates a Stake DAO market on Curve using a cryptoswap oracle
    /// @dev The lending factory must be trusted!
    ///      The ownership of this contract is propagated to the lending factory
    /// @param rewardVault The reward vault to use for the market
    /// @param oracleParams The parameters for the cryptoswap oracle
    /// @param marketParams The parameters for the market
    /// @param lendingFactory The factory to use for the market
    function deploy(
        IRewardVault rewardVault,
        CryptoswapOracleParams calldata oracleParams,
        MarketParams calldata marketParams,
        ILendingFactory lendingFactory
    ) external onlyOwner isValidDeployment(rewardVault) returns (IStrategyWrapper, IOracle, bytes memory) {
        // 1. Deploy the collateral token
        IStrategyWrapper collateral = _deployCollateral(rewardVault, lendingFactory);

        // 2. Deploy the oracle
        IOracle oracle = new CurveCryptoswapOracle(
            META_REGISTRY.get_pool_from_lp_token(rewardVault.asset()),
            address(collateral),
            oracleParams.loanAsset,
            oracleParams.loanAssetFeed,
            oracleParams.loanAssetFeedHeartbeat,
            oracleParams.token0ToUsdFeeds,
            oracleParams.token0ToUsdHeartbeats
        );
        emit OracleDeployed(address(oracle));

        // 3. Create the lending market
        bytes memory data = _createMarket(collateral, oracle, oracleParams.loanAsset, lendingFactory, marketParams);
        return (collateral, oracle, data);
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _deployCollateral(IRewardVault rewardVault, ILendingFactory lendingFactory)
        internal
        returns (IStrategyWrapper)
    {
        IStrategyWrapper collateral = new RestrictedStrategyWrapper(rewardVault, lendingFactory.protocol(), owner());
        emit CollateralDeployed(address(collateral));

        return collateral;
    }

    function _createMarket(
        IStrategyWrapper collateral,
        IOracle oracle,
        address loanAsset,
        ILendingFactory lendingFactory,
        MarketParams calldata marketParams
    ) internal returns (bytes memory) {
        (bool success, bytes memory data) = address(lendingFactory).delegatecall(
            abi.encodeWithSelector(
                lendingFactory.create.selector,
                address(collateral),
                loanAsset,
                address(oracle),
                marketParams.irm,
                marketParams.lltv,
                marketParams.initialSupply
            )
        );
        require(success, MarketCreationFailed());

        return data;
    }

    ///////////////////////////////////////////////////////////////
    // --- GETTERS
    ///////////////////////////////////////////////////////////////

    /// @return version The version of the factory.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @return identifier The identifier of the factory.
    function identifier() external pure returns (string memory) {
        return type(CurveLendingMarketFactory).name;
    }
}
