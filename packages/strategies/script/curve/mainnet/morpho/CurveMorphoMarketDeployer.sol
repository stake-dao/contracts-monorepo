// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {MarketParams, Id} from "shared/src/morpho/IMorpho.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {ILendingFactory} from "src/interfaces/ILendingFactory.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";

abstract contract CurveMorphoMarketDeployer is Script {
    struct Inputs {
        address factory;
        address rewardVault;
        address irm;
        uint256 lltv;
        address loanAsset;
        address loanAssetFeed;
        uint256 loanAssetFeedHeartbeat;
        address[] chainlinkFeeds;
        uint256[] chainlinkFeedHeartbeats;
        address lendingFactory;
        uint256 initialSupply;
    }

    function run() external virtual returns (bytes memory);

    function _run(CurveLendingMarketFactory.OracleType oracleType) internal virtual returns (bytes memory) {
        Inputs memory inputs = _getAndParseInput(oracleType);

        // 1. Build parameters
        CurveLendingMarketFactory.MarketParams memory marketParams =
            CurveLendingMarketFactory.MarketParams(inputs.irm, inputs.lltv, inputs.initialSupply);

        CurveLendingMarketFactory.OracleParams memory oracleParams = CurveLendingMarketFactory.OracleParams({
            loanAsset: inputs.loanAsset,
            loanAssetFeed: inputs.loanAssetFeed,
            loanAssetFeedHeartbeat: inputs.loanAssetFeedHeartbeat,
            chainlinkFeeds: inputs.chainlinkFeeds,
            chainlinkFeedHeartbeats: inputs.chainlinkFeedHeartbeats
        });

        // 2. Validate with the deployer the parameters before deploying
        _validateParameters(IRewardVault(inputs.rewardVault), marketParams, oracleParams, oracleType);

        // 3. Deploy the market
        vm.startBroadcast();
        (IStrategyWrapper wrapper, IOracle oracle, bytes memory data) = CurveLendingMarketFactory(inputs.factory).deploy(
            IRewardVault(inputs.rewardVault),
            oracleType,
            oracleParams,
            marketParams,
            ILendingFactory(inputs.lendingFactory)
        );
        vm.stopBroadcast();

        // 4. Confirm the deployed market
        _confirmationPrompt(inputs.loanAsset, oracle, wrapper, data);

        return data;
    }

    function _getAndParseInput(CurveLendingMarketFactory.OracleType oracleType)
        internal
        virtual
        returns (Inputs memory inputs)
    {
        inputs.factory = vm.envAddress("CURVE_LENDING_MARKET_FACTORY");
        inputs.rewardVault = vm.envAddress("REWARD_VAULT");
        inputs.irm = vm.envAddress("IRM");
        inputs.lltv = vm.envUint("LLTV");
        inputs.loanAsset = vm.envAddress("LOAN_ASSET");
        inputs.loanAssetFeed = vm.envAddress("LOAN_ASSET_FEED");
        inputs.loanAssetFeedHeartbeat = vm.envUint("LOAN_ASSET_FEED_HEARTBEAT");
        inputs.chainlinkFeeds = vm.envAddress("CHAINLINK_FEEDS", ",");
        inputs.chainlinkFeedHeartbeats = vm.envUint("CHAINLINK_FEEDS_HEARTBEAT", ",");
        inputs.lendingFactory = vm.envAddress("LENDING_FACTORY");
        inputs.initialSupply = vm.envUint("INITIAL_SUPPLY");

        require(inputs.factory.code.length > 0, "CurveLendingMarketFactory not deployed");
        require(inputs.rewardVault.code.length > 0, "RewardVault not deployed");
        require(inputs.loanAsset != address(0), "Invalid loan asset");
        require(inputs.loanAssetFeed.code.length > 0, "Invalid Loan Asset Feed");
        require(inputs.loanAssetFeedHeartbeat > 0, "Invalid Loan Asset Heartbeat");
        require(
            inputs.chainlinkFeeds.length == inputs.chainlinkFeedHeartbeats.length,
            "Invalid Chainlink Feeds/Heartbeats length"
        );
        for (uint256 i; i < inputs.chainlinkFeeds.length; i++) {
            if (inputs.chainlinkFeeds[i] != address(0) && inputs.chainlinkFeedHeartbeats[i] == 0) {
                revert("Invalid hearbeats");
            }
        }
        require(inputs.lendingFactory.code.length > 0, "LendingFactory not deployed");

        // There is case where the cryptoswap oracles doesn't need any chainlink feed
        if (oracleType == CurveLendingMarketFactory.OracleType.STABLESWAP) {
            require(inputs.chainlinkFeeds.length > 0, "Invalid Chainlink Feeds");
        }
    }

    function _confirmationPrompt(address loanAsset, IOracle oracle, IStrategyWrapper wrapper, bytes memory data)
        internal
        virtual
    {
        uint256 priceWei = oracle.price() / 10 ** (36 + IERC20Metadata(loanAsset).decimals() - wrapper.decimals());
        console.log(
            "The LP token is priced %d.%d %s.",
            priceWei / 10 ** IERC20Metadata(loanAsset).decimals(),
            priceWei % 10 ** IERC20Metadata(loanAsset).decimals(),
            IERC20Metadata(loanAsset).symbol()
        );
        string memory answer = vm.prompt("Does it make sense to you? (y/n)");
        if (keccak256(bytes(answer)) != keccak256(bytes("y")) && keccak256(bytes(answer)) != keccak256(bytes("yes"))) {
            revert("Deployment cancelled by user");
        }

        console.log("--------------------------------");
        console.log("The market is deployed. You can now start borrowing from it.");
        console.log("Oracle: %s", address(oracle));
        console.log("Wrapper: %s", address(wrapper));
        console.log("Market ID: %s", vm.toString(abi.decode(data, (bytes32))));
        console.log("--------------------------------");
    }

    function _validateParameters(
        IRewardVault rewardVault,
        CurveLendingMarketFactory.MarketParams memory marketParams,
        CurveLendingMarketFactory.OracleParams memory oracleParams,
        CurveLendingMarketFactory.OracleType oracleType
    ) internal virtual {
        console.log("--------------------------------");
        console.log(
            "You are about to deploy a lending market based on a Curve %s pool.",
            oracleType == CurveLendingMarketFactory.OracleType.STABLESWAP ? "Stableswap" : "Cryptoswap"
        );
        console.log("Here's the parameters of the market you are about to deploy:");
        console.log("- Reward Vault that will be wrapped: %s [%s]", address(rewardVault), rewardVault.name());
        console.log("- Curve Pool: %s [%s]", rewardVault.asset(), IERC20Metadata(rewardVault.asset()).name());
        console.log("- Loan Asset: %s [%s]", oracleParams.loanAsset, IERC20Metadata(oracleParams.loanAsset).name());
        console.log(
            "- Oracle Type: %s",
            oracleType == CurveLendingMarketFactory.OracleType.STABLESWAP ? "STABLESWAP" : "CRYPTOSWAP"
        );
        console.log("- IRM: %s", marketParams.irm);
        console.log("- LLTV: %s", marketParams.lltv);
        console.log("--------------------------------");
        console.log("Pool assets and their USD feeds:");
        for (uint256 i = 0; i < oracleParams.chainlinkFeeds.length; i++) {
            if (oracleType == CurveLendingMarketFactory.OracleType.STABLESWAP) {
                // For stableswap: each feed prices a pool asset
                address poolAsset = ICurvePool(rewardVault.asset()).coins(i);
                console.log(
                    "- Asset: %s [%s] -> Feed: %s",
                    poolAsset,
                    IERC20Metadata(poolAsset).name(),
                    IChainlinkFeed(oracleParams.chainlinkFeeds[i]).description()
                );
            } else {
                // For cryptoswap: feeds convert token0 to USD step by step
                console.log("- Hop %d: %s", i, IChainlinkFeed(oracleParams.chainlinkFeeds[i]).description());
            }
        }
        console.log("--------------------------------");
        if (oracleType == CurveLendingMarketFactory.OracleType.STABLESWAP) {
            console.log("Oracle will use MINIMUM price among pool assets for conservative valuation.");
        } else {
            console.log("Oracle will convert token0 to USD through the feed chain, then to loan asset.");
        }
        console.log("--------------------------------");
        console.log(
            "Please, double check the heartbeats and the feeds you provided here %s (%s)",
            "https://docs.chain.link/data-feeds/price-feeds/addresses",
            "Only Chainlink compliant oracles are supported"
        );
        console.log("--------------------------------");
        string memory answer = vm.prompt("Are you sure you want to deploy this market? (y/n)");
        if (keccak256(bytes(answer)) != keccak256(bytes("y")) && keccak256(bytes(answer)) != keccak256(bytes("yes"))) {
            revert("Deployment cancelled by user");
        }
    }
}
