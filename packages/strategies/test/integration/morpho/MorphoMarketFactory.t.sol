// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {CurveMainnetIntegrationTest} from "test/integration/curve/mainnet/CurveMainnetIntegration.t.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IMorpho,
    Market as MorphoMarketState,
    Id as MorphoId,
    Position as MorphoPosition
} from "shared/src/morpho/IMorpho.sol";

contract MorphoMarketFactoryIntegrationTest is CurveMainnetIntegrationTest {
    MorphoMarketFactory internal morphoMarketFactory;
    IMorpho internal constant MORPHO = IMorpho(Common.MORPHO_BLUE);

    uint256[] internal $poolIds;

    /// @dev Override the block number to a specific date. Here's some token prices at this block:
    ///      - BTC is $109,174
    ///      - ETH is $2,571
    function getConfig() internal view virtual override returns (Config memory) {
        Config memory config = super.getConfig();
        config.base.blockNumber = 22_867_994; // July the 7th at ~14:45 UTC
        return config;
    }

    function _stableSwapPools() internal pure returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](3);
        _poolIds[0] = 440; // reUSD/scrvUSD (0xc522A6606BBA746d7960404F22a3DB936B6F4F50)
        _poolIds[1] = 392; // cbBTC/wBTC (0x839d6bDeDFF886404A6d7a788ef241e4e28F4802)
        _poolIds[2] = 155; // wETH/stETH (0x828b154032950C8ff7CF8085D841723Db2696056)
        return _poolIds;
    }

    function _cryptoSwapPools() internal pure returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](3);
        _poolIds[0] = 188; // USDT/wBTC/ETH (0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4)
        _poolIds[1] = 409; // GHO/cbBTC/wETH (0x8a4f252812dff2a8636e4f7eb249d8fc2e3bd77f)
        _poolIds[2] = 441; // wETH/RSUP (0xee351f12eae8c2b8b9d1b9bfd3c5dd565234578d)
        return _poolIds;
    }

    function poolIds() public view virtual override returns (uint256[] memory) {
        return $poolIds;
    }

    // @dev Only fuzz three different account positions
    //      Trust me it works with this hardcoded value despite the bound function
    function MAX_ACCOUNT_POSITIONS() public virtual override returns (uint256) {
        return 3;
    }

    constructor() CurveMainnetIntegrationTest() {
        uint256[] memory stablePools = _stableSwapPools();
        for (uint256 i; i < stablePools.length; i++) {
            $poolIds.push(stablePools[i]);
        }
        uint256[] memory cryptoPools = _cryptoSwapPools();
        for (uint256 i; i < cryptoPools.length; i++) {
            $poolIds.push(cryptoPools[i]);
        }

        vm.label(Common.MORPHO_ADAPTIVE_CURVE_IRM, "IRM");
        vm.label(Common.USDC, "USDC");
        vm.label(address(morphoMarketFactory), "MorphoBlue");

        vm.label(0xc522A6606BBA746d7960404F22a3DB936B6F4F50, "reUSD/scrvUSD");
        vm.label(0x839d6bDeDFF886404A6d7a788ef241e4e28F4802, "cbBTC/wBTC");
        vm.label(0x828b154032950C8ff7CF8085D841723Db2696056, "wETH/stETH");
        vm.label(0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4, "USDT/wBTC/ETH");
        vm.label(0x8a4f252812dFF2A8636E4F7EB249d8FC2E3bd77f, "GHO/cbBTC/wETH");
        vm.label(0xEe351f12EAE8C2B8B9d1B9BFd3c5dd565234578d, "wETH/RSUP");
    }

    function test_complete_protocol_lifecycle() public override {}

    function test_create_stableswap_markets() external {
        // Fuzz an account position and reward amount
        (AccountPosition[] memory _accountPositions,) = _generateAccountPositionsAndRewards();

        // Deploy the reward vault
        (RewardVault[] memory vaults,) = deployRewardVaults();

        uint256[] memory lltvs = new uint256[](3);
        lltvs[0] = 980 * 1e15; // 98%
        lltvs[1] = 965 * 1e15; // 96.5%
        lltvs[2] = 945 * 1e15; // 94.5%

        address[] memory baseFeeds = new address[](3);
        baseFeeds[0] = address(0); // no need, already denominated in USD
        baseFeeds[1] = 0x2665701293fCbEB223D11A08D826563EDcCE423A; // cbBTC/USD
        baseFeeds[2] = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD (ETH<>wETH 1:1)

        uint256[] memory baseFeedHeartbeats = new uint256[](3);
        baseFeedHeartbeats[0] = 0;
        baseFeedHeartbeats[1] = 86400; // 1 day
        baseFeedHeartbeats[2] = 3600; // 1 hour

        uint256 stablePoolsLength = _stableSwapPools().length;
        // Deploy the different markets
        for (uint256 i; i < stablePoolsLength; i++) {
            _test_stableswap_market_creation(
                _accountPositions[i], lltvs[i], baseFeeds[i], baseFeedHeartbeats[i], vaults[i]
            );
        }
    }

    function _test_stableswap_market_creation(
        AccountPosition memory position,
        uint256 lltv,
        address baseFeed,
        uint256 baseFeedHeartbeat,
        RewardVault rewardVault
    ) internal {
        // Deploy the Curve lending market factory
        vm.prank(position.account);
        CurveLendingMarketFactory curveLendingMarketFactory = new CurveLendingMarketFactory(address(protocolController));
        vm.label(address(curveLendingMarketFactory), "CurveLendingMarketFactory");

        // Deploy the Morpho market factory
        vm.prank(position.account);
        morphoMarketFactory = new MorphoMarketFactory(address(MORPHO));
        vm.label(address(morphoMarketFactory), "MorphoMarketFactory");

        // Setup the market parameters
        CurveLendingMarketFactory.MarketParams memory marketParams =
            CurveLendingMarketFactory.MarketParams({irm: Common.MORPHO_ADAPTIVE_CURVE_IRM, lltv: lltv});

        // Setup the oracle parameters
        CurveLendingMarketFactory.StableswapOracleParams memory oracleParams = CurveLendingMarketFactory
            .StableswapOracleParams({
            loanAsset: Common.USDC,
            loanAssetFeed: Common.CHAINLINK_USDC_USD_PRICE_FEED,
            loanAssetFeedHeartbeat: 86_400,
            baseFeed: baseFeed,
            baseFeedHeartbeat: baseFeedHeartbeat
        });
        vm.label(Common.CHAINLINK_USDC_USD_PRICE_FEED, "USDC/USD Chainlink Feed");

        // Deposit some Curve LP tokens into the reward vault
        deposit(rewardVault, position.account, position.baseAmount);
        assertEq(rewardVault.balanceOf(position.account), position.baseAmount);

        // Deal $1 of USDC (loan asset) to the user
        address loanAsset = Common.USDC;
        uint256 loanInitialBalance = 10 ** IERC20Metadata(loanAsset).decimals();
        deal(loanAsset, position.account, loanInitialBalance);

        // Approve the curve lending factory to spend the USDC
        vm.prank(position.account);
        IERC20(loanAsset).approve(address(curveLendingMarketFactory), loanInitialBalance);

        // Approve the curve lending factory to spend the reward vault shares
        vm.prank(position.account);
        rewardVault.approve(address(curveLendingMarketFactory), position.baseAmount);

        // Authorize the curve lending factory to manages user's positions
        vm.prank(position.account);
        MORPHO.setAuthorization(address(curveLendingMarketFactory), true);

        // Deploy the market
        vm.prank(position.account);
        (,, bytes memory data) =
            curveLendingMarketFactory.deploy(rewardVault, oracleParams, marketParams, morphoMarketFactory);

        assertEq(
            IERC20(loanAsset).balanceOf(position.account), uint256(9 * 10 ** IERC20Metadata(loanAsset).decimals()) / 10
        );

        MorphoId marketID = abi.decode(data, (MorphoId));
        {
            MorphoMarketState memory market = MORPHO.market(marketID);
            assertEq(market.totalSupplyAssets, 10 ** IERC20Metadata(loanAsset).decimals());
            assertGt(market.totalSupplyShares, 0);
            assertEq(market.totalBorrowAssets, (10 ** IERC20Metadata(loanAsset).decimals() * 9) / 10);
            assertEq(market.lastUpdate, block.timestamp);
        }

        MorphoPosition memory morphoPosition = MORPHO.position(marketID, address(position.account));
        {
            assertEq(MORPHO.market(marketID).totalBorrowShares, morphoPosition.borrowShares);
            assertEq(morphoPosition.supplyShares - morphoPosition.borrowShares, morphoPosition.supplyShares / 10); // 90%

            morphoPosition = MORPHO.position(marketID, address(morphoMarketFactory));
            assertEq(morphoPosition.supplyShares, 0);
            assertEq(morphoPosition.borrowShares, 0);
            assertEq(morphoPosition.collateral, 0);
        }
    }

    function test_create_cryptoswap_markets() external {
        // Fuzz an account position and reward amount
        (AccountPosition[] memory _accountPositions,) = _generateAccountPositionsAndRewards();

        // Deploy the reward vault
        (RewardVault[] memory vaults,) = deployRewardVaults();

        uint256[] memory lltvs = new uint256[](3);
        lltvs[0] = 980 * 1e15; // 98%
        lltvs[1] = 965 * 1e15; // 96.5%
        lltvs[2] = 945 * 1e15; // 94.5%

        address[][] memory token0ToUsdFeeds = new address[][](3);
        token0ToUsdFeeds[0] = new address[](1);
        token0ToUsdFeeds[0][0] = Common.CHAINLINK_USDT_USD_PRICE_FEED;
        token0ToUsdFeeds[1] = new address[](1);
        token0ToUsdFeeds[1][0] = 0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC; // GHO/USD
        token0ToUsdFeeds[2] = new address[](1);
        token0ToUsdFeeds[2][0] = Common.CHAINLINK_ETH_USD_PRICE_FEED;

        uint256[][] memory token0ToUsdHeartbeats = new uint256[][](3);
        token0ToUsdHeartbeats[0] = new uint256[](1);
        token0ToUsdHeartbeats[0][0] = 86400; // 1 day
        token0ToUsdHeartbeats[1] = new uint256[](1);
        token0ToUsdHeartbeats[1][0] = 86400; // 1 day
        token0ToUsdHeartbeats[2] = new uint256[](1);
        token0ToUsdHeartbeats[2][0] = 3600; // 1 hour

        // Deploy the different markets
        uint256 cryptoPoolsLength = _cryptoSwapPools().length;
        uint256 stablePoolsLength = _stableSwapPools().length;

        for (uint256 i; i < cryptoPoolsLength; i++) {
            _test_cryptoswap_market_creation(
                _accountPositions[i],
                lltvs[i],
                token0ToUsdFeeds[i],
                token0ToUsdHeartbeats[i],
                vaults[i + stablePoolsLength]
            );
        }
    }

    function _test_cryptoswap_market_creation(
        AccountPosition memory position,
        uint256 lltv,
        address[] memory token0ToUsdFeeds,
        uint256[] memory token0ToUsdHeartbeats,
        RewardVault rewardVault
    ) internal {
        // Deploy the Curve lending market factory
        vm.prank(position.account);
        CurveLendingMarketFactory curveLendingMarketFactory = new CurveLendingMarketFactory(address(protocolController));
        vm.label(address(curveLendingMarketFactory), "CurveLendingMarketFactory");

        // Deploy the Morpho market factory
        vm.prank(position.account);
        morphoMarketFactory = new MorphoMarketFactory(address(MORPHO));
        vm.label(address(morphoMarketFactory), "MorphoMarketFactory");

        // Setup the market parameters
        CurveLendingMarketFactory.MarketParams memory marketParams =
            CurveLendingMarketFactory.MarketParams({irm: Common.MORPHO_ADAPTIVE_CURVE_IRM, lltv: lltv});

        // Setup the oracle parameters
        CurveLendingMarketFactory.CryptoswapOracleParams memory oracleParams = CurveLendingMarketFactory
            .CryptoswapOracleParams({
            loanAsset: Common.USDC,
            loanAssetFeed: Common.CHAINLINK_USDC_USD_PRICE_FEED,
            loanAssetFeedHeartbeat: 86_400,
            token0ToUsdFeeds: token0ToUsdFeeds,
            token0ToUsdHeartbeats: token0ToUsdHeartbeats
        });
        vm.label(Common.CHAINLINK_USDC_USD_PRICE_FEED, "USDC/USD Chainlink Feed");

        // Deposit some Curve LP tokens into the reward vault
        deposit(rewardVault, position.account, position.baseAmount);
        assertEq(rewardVault.balanceOf(position.account), position.baseAmount);

        // Deal $1 of USDC (loan asset) to the user
        address loanAsset = Common.USDC;
        uint256 loanInitialBalance = 10 ** IERC20Metadata(loanAsset).decimals();
        deal(loanAsset, position.account, loanInitialBalance);

        // Approve the curve lending factory to spend the USDC
        vm.prank(position.account);
        IERC20(loanAsset).approve(address(curveLendingMarketFactory), loanInitialBalance);

        // Approve the curve lending factory to spend the reward vault shares
        vm.prank(position.account);
        rewardVault.approve(address(curveLendingMarketFactory), position.baseAmount);

        // Authorize the curve lending factory to manages user's positions
        vm.prank(position.account);
        MORPHO.setAuthorization(address(curveLendingMarketFactory), true);

        // Deploy the market
        vm.prank(position.account);
        (,, bytes memory data) =
            curveLendingMarketFactory.deploy(rewardVault, oracleParams, marketParams, morphoMarketFactory);

        assertEq(
            IERC20(loanAsset).balanceOf(position.account), uint256(9 * 10 ** IERC20Metadata(loanAsset).decimals()) / 10
        );

        MorphoId marketID = abi.decode(data, (MorphoId));
        MorphoPosition memory morphoPosition = MORPHO.position(marketID, address(position.account));
        MorphoMarketState memory market = MORPHO.market(marketID);
        {
            assertEq(market.totalSupplyAssets, 10 ** IERC20Metadata(loanAsset).decimals());
            assertGt(market.totalSupplyShares, 0);
            assertEq(market.totalBorrowAssets, (10 ** IERC20Metadata(loanAsset).decimals() * 9) / 10);
            assertEq(market.lastUpdate, block.timestamp);

            assertEq(market.totalBorrowShares, morphoPosition.borrowShares);
            assertEq(morphoPosition.supplyShares - morphoPosition.borrowShares, morphoPosition.supplyShares / 10); // 90%

            morphoPosition = MORPHO.position(marketID, address(morphoMarketFactory));
            assertEq(morphoPosition.supplyShares, 0);
            assertEq(morphoPosition.borrowShares, 0);
            assertEq(morphoPosition.collateral, 0);
        }
    }
}
