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

    /// @dev Thrown when the oracle type is invalid.
    error InvalidOracleType();

    /// @dev Thrown when the delegate call fails.
    error MarketCreationFailed();

    enum OracleType {
        UNKNOWN, // safeguard against using the default value
        STABLESWAP,
        CRYPTOSWAP
    }

    /// @dev The parameters for creating a Curve oracle (both stableswap and cryptoswap).
    struct OracleParams {
        address loanAsset;
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address[] chainlinkFeeds; // For stableswap: pool asset feeds. For cryptoswap: token0→USD feeds
        uint256[] chainlinkFeedHeartbeats;
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

    modifier isValidDeployment(IRewardVault rewardVault, OracleType oracleType) {
        require(PROTOCOL_CONTROLLER.vaults(rewardVault.gauge()) == address(rewardVault), InvalidRewardVault());
        require(rewardVault.PROTOCOL_ID() == bytes4(keccak256("CURVE")), InvalidProtocolId());
        require(oracleType != OracleType.UNKNOWN, InvalidOracleType());
        _;
    }

    ///////////////////////////////////////////////////////////////
    // --- MARKET CREATION
    ///////////////////////////////////////////////////////////////

    /// @notice Creates a Stake DAO market on Curve with the specified oracle type
    /// @dev The lending factory must be trusted!
    ///      The ownership of this contract is propagated to the lending factory
    /// @param rewardVault The reward vault to use for the market
    /// @param oracleType The type of oracle to deploy (STABLESWAP =1 or CRYPTOSWAP =2)
    /// @param oracleParams The parameters for the oracle (structure works for both types)
    /// @param marketParams The parameters for the market
    /// @param lendingFactory The factory to use for the market
    function deploy(
        IRewardVault rewardVault,
        OracleType oracleType,
        OracleParams calldata oracleParams,
        MarketParams calldata marketParams,
        ILendingFactory lendingFactory
    ) external onlyOwner isValidDeployment(rewardVault, oracleType) returns (IStrategyWrapper, IOracle, bytes memory) {
        // 1. Deploy the collateral token
        IStrategyWrapper collateral = _deployCollateral(rewardVault, lendingFactory);

        // 2. Deploy the oracle
        IOracle oracle = _deployOracle(
            collateral, META_REGISTRY.get_pool_from_lp_token(rewardVault.asset()), oracleType, oracleParams
        );

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

    function _deployOracle(
        IStrategyWrapper collateral,
        address curvePool,
        OracleType oracleType,
        OracleParams calldata oracleParams
    ) internal returns (IOracle oracle) {
        if (oracleType == OracleType.CRYPTOSWAP) {
            oracle = new CurveCryptoswapOracle(
                curvePool,
                address(collateral),
                oracleParams.loanAsset,
                oracleParams.loanAssetFeed,
                oracleParams.loanAssetFeedHeartbeat,
                oracleParams.chainlinkFeeds,
                oracleParams.chainlinkFeedHeartbeats
            );
        } else if (oracleType == OracleType.STABLESWAP) {
            oracle = new CurveStableswapOracle(
                curvePool,
                address(collateral),
                oracleParams.loanAsset,
                oracleParams.loanAssetFeed,
                oracleParams.loanAssetFeedHeartbeat,
                oracleParams.chainlinkFeeds,
                oracleParams.chainlinkFeedHeartbeats
            );
        } else {
            revert InvalidOracleType();
        }
        emit OracleDeployed(address(oracle));

        return oracle;
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
}
