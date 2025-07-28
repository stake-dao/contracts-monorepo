// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {MarketParams, Id} from "shared/src/morpho/IMorpho.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {ILendingFactory} from "src/interfaces/ILendingFactory.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";

contract DeployCurveCryptoMarketScript is Script {
    function run() external returns (bytes memory) {
        address factory = vm.envAddress("CURVE_LENDING_MARKET_FACTORY");
        address rewardVault = vm.envAddress("REWARD_VAULT");
        address irm = vm.envAddress("IRM");
        uint256 lltv = vm.envUint("LLTV");
        address loanAsset = vm.envAddress("LOAN_ASSET");
        address loanAssetFeed = vm.envAddress("LOAN_ASSET_FEED");
        uint256 loanAssetFeedHeartbeat = vm.envUint("LOAN_ASSET_FEED_HEARTBEAT");
        address[] memory token0ToUsdFeeds = vm.envAddress("TOKEN_TO_USD_FEEDS", ",");
        uint256[] memory token0ToUsdHeartbeats = vm.envUint("TOKEN_TO_USD_FEEDS_HEARTBEAT", ",");
        address lendingFactory = vm.envAddress("LENDING_FACTORY");

        require(factory.code.length > 0, "CurveLendingMarketFactory not deployed");
        require(rewardVault.code.length > 0, "RewardVault not deployed");
        require(loanAsset != address(0), "Invalid loan asset");
        require(token0ToUsdFeeds.length == token0ToUsdHeartbeats.length, "Invalid Feeds/Heartbeats length");
        for (uint256 i; i < token0ToUsdFeeds.length; i++) {
            if (token0ToUsdFeeds[i] != address(0) && token0ToUsdHeartbeats[i] == 0) revert("Invalid hearbeats");
        }
        require(lendingFactory.code.length > 0, "LendingFactory not deployed");

        CurveLendingMarketFactory.MarketParams memory marketParams =
            CurveLendingMarketFactory.MarketParams(irm, lltv, vm.envUint("INITIAL_SUPPLY"));

        CurveLendingMarketFactory.CryptoswapOracleParams memory oracleParams = CurveLendingMarketFactory
            .CryptoswapOracleParams({
            loanAsset: loanAsset,
            loanAssetFeed: loanAssetFeed,
            loanAssetFeedHeartbeat: loanAssetFeedHeartbeat,
            token0ToUsdFeeds: token0ToUsdFeeds,
            token0ToUsdHeartbeats: token0ToUsdHeartbeats
        });

        _validationPrompt(IRewardVault(rewardVault), marketParams, oracleParams);

        vm.startBroadcast();
        (IStrategyWrapper wrapper, IOracle oracle, bytes memory data) = CurveLendingMarketFactory(factory).deploy(
            IRewardVault(rewardVault), oracleParams, marketParams, ILendingFactory(lendingFactory)
        );
        vm.stopBroadcast();

        _confirmationPrompt(loanAsset, oracle, wrapper);
        console.log("--------------------------------");
        console.log("The market is deployed. You can now start borrowing from it.");
        console.log("Oracle: %s", address(oracle));
        console.log("Wrapper: %s", address(wrapper));
        console.log("Market ID: %s", vm.toString(abi.decode(data, (bytes32))));
        console.log("--------------------------------");

        return data;
    }

    function _confirmationPrompt(address loanAsset, IOracle oracle, IStrategyWrapper wrapper) internal {
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
    }

    function _validationPrompt(
        IRewardVault rewardVault,
        CurveLendingMarketFactory.MarketParams memory marketParams,
        CurveLendingMarketFactory.CryptoswapOracleParams memory oracleParams
    ) internal {
        console.log("--------------------------------");
        console.log("You are about to deploy a Morpho Crypto Market.");
        console.log("Here's the parameters of the market you are about to deploy:");
        console.log("- Reward Vault that will be wrapped: %s [%s]", address(rewardVault), rewardVault.name());
        console.log("- Curve Pool: %s [%s]", rewardVault.asset(), IERC20Metadata(rewardVault.asset()).name());
        console.log("- Loan Asset: %s [%s]", oracleParams.loanAsset, IERC20Metadata(oracleParams.loanAsset).name());
        console.log("- IRM: %s", marketParams.irm);
        console.log("- LLTV: %s", marketParams.lltv);
        console.log("--------------------------------");
        console.log(
            "The first token of the Curve Pool is %s [%s]. The first provided feed must convert from this token",
            ICurvePool(rewardVault.asset()).coins(0),
            IERC20Metadata(ICurvePool(rewardVault.asset()).coins(0)).name()
        );
        console.log("--------------------------------");
        console.log("The conversion from the LP token to the loan asset will follow this path:");
        string memory paths = "";
        for (uint256 i; i < oracleParams.token0ToUsdFeeds.length; i++) {
            paths = string.concat(paths, IChainlinkFeed(oracleParams.token0ToUsdFeeds[i]).description(), " -> ");
        }
        paths = string.concat(IChainlinkFeed(oracleParams.loanAssetFeed).description());
        console.log("Path: %s (last feed is reverted on purpose)", paths);
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
