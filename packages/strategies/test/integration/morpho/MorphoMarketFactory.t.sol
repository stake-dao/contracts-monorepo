// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {CurveMainnetIntegrationTest} from "test/integration/curve/mainnet/CurveMainnetIntegration.t.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {StrategyWrapper} from "src/wrappers/StrategyWrapper.sol";
import {
    IMorpho,
    Market as MorphoMarketState,
    Id as MorphoId,
    Position as MorphoPosition
} from "shared/src/morpho/IMorpho.sol";

contract MorphoMarketFactoryIntegrationTest is CurveMainnetIntegrationTest {
    MorphoMarketFactory internal morphoMarketFactory;
    IMorpho internal constant MORPHO = IMorpho(Common.MORPHO_BLUE);

    /// @dev Override the block number to a specific date. Here's some token prices at this block:
    ///      - BTC is $109,174
    ///      - ETH is $2,571
    function getConfig() internal view virtual override returns (Config memory) {
        Config memory config = super.getConfig();
        config.base.blockNumber = 22_867_994; // July the 7th at ~14:45 UTC
        return config;
    }

    function poolIds() public view virtual override returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](_stableSwapPools().length + _cryptoSwapPools().length);

        uint256 stableLength = _stableSwapPools().length;
        for (uint256 i; i < stableLength; i++) {
            _poolIds[i] = _stableSwapPools()[i];
        }

        uint256 cryptoLength = _cryptoSwapPools().length;
        for (uint256 i; i < cryptoLength; i++) {
            _poolIds[i + stableLength] = _cryptoSwapPools()[i];
        }

        return _poolIds;
    }

    function _stableSwapPools() internal pure returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](3);
        _poolIds[0] = 425; // USDC/USDT (0x4f493b7de8aac7d55f71853688b1f7c8f0243c85)
        _poolIds[1] = 392; // cbBTC/wBTC (0x839d6bDeDFF886404A6d7a788ef241e4e28F4802)
        _poolIds[2] = 177; // ETH/stETH (0x21E27a5E5513D6e65C4f830167390997aA84843a)
        return _poolIds;
    }

    function _cryptoSwapPools() internal pure returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](3);
        _poolIds[0] = 188; // USDT/wBTC/ETH (0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4)
        _poolIds[1] = 409; // GHO/cbBTC/wETH (0x8a4f252812dff2a8636e4f7eb249d8fc2e3bd77f)
        _poolIds[2] = 441; // wETH/RSUP (0xee351f12eae8c2b8b9d1b9bfd3c5dd565234578d)
        return _poolIds;
    }

    // @dev Only fuzz three different account positions
    //      Trust me it works with this hardcoded value despite the bound function
    function MAX_ACCOUNT_POSITIONS() public virtual override returns (uint256) {
        return 3;
    }

    constructor() CurveMainnetIntegrationTest() {
        vm.label(Common.MORPHO_ADAPTIVE_CURVE_IRM, "IRM");
        vm.label(Common.USDC, "USDC");
        vm.label(address(morphoMarketFactory), "MorphoMarketFactory");
        vm.label(address(MORPHO), "Morpho");

        vm.label(0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85, "USDC/USDT");
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

        // Stableswap pools require feeds for each pool asset
        address[][] memory poolAssetFeeds = new address[][](3);

        // Pool 0: USDC/USDT - both USD stablecoins
        poolAssetFeeds[0] = new address[](0);

        // Pool 1: cbBTC/wBTC - both BTC derivatives
        poolAssetFeeds[1] = new address[](1);
        poolAssetFeeds[1][0] = 0x2665701293fCbEB223D11A08D826563EDcCE423A; // cbBTC/USD

        // Pool 2: wETH/stETH - both ETH derivatives
        poolAssetFeeds[2] = new address[](1);
        poolAssetFeeds[2][0] = 0x5424384B256154046E9667dDFaaa5e550145215e; // ETH/USD (wETH is 1:1 with ETH)

        uint256[][] memory poolAssetHeartbeats = new uint256[][](3);
        poolAssetHeartbeats[0] = new uint256[](0);
        poolAssetHeartbeats[1] = new uint256[](1);
        poolAssetHeartbeats[1][0] = 1 days;
        poolAssetHeartbeats[2] = new uint256[](1);
        poolAssetHeartbeats[2][0] = 1 hours;

        uint256 stablePoolsLength = _stableSwapPools().length;
        // Deploy the different markets
        for (uint256 i; i < stablePoolsLength; i++) {
            _test_market_creation(
                _accountPositions[i],
                lltvs[i],
                poolAssetFeeds[i],
                poolAssetHeartbeats[i],
                vaults[i],
                CurveLendingMarketFactory.OracleType.STABLESWAP
            );
        }
    }

    function skip_test_create_cryptoswap_markets() external {
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
            _test_market_creation(
                _accountPositions[i],
                lltvs[i],
                token0ToUsdFeeds[i],
                token0ToUsdHeartbeats[i],
                vaults[i + stablePoolsLength],
                CurveLendingMarketFactory.OracleType.CRYPTOSWAP
            );
        }
    }

    /// @notice Unified function to test market creation for both stableswap and cryptoswap oracles
    function _test_market_creation(
        AccountPosition memory position,
        uint256 lltv,
        address[] memory chainlinkFeeds,
        uint256[] memory chainlinkFeedHeartbeats,
        RewardVault rewardVault,
        CurveLendingMarketFactory.OracleType oracleType
    ) internal {
        address deployer = position.account;
        // Deploy the Curve lending market factory
        vm.prank(deployer);
        CurveLendingMarketFactory curveLendingMarketFactory = new CurveLendingMarketFactory(address(protocolController));
        vm.label(address(curveLendingMarketFactory), "CurveLendingMarketFactory");

        // Deploy the Morpho market factory
        vm.prank(deployer);
        morphoMarketFactory = new MorphoMarketFactory(address(MORPHO));
        vm.label(address(morphoMarketFactory), "MorphoMarketFactory");

        // Setup the market parameters
        CurveLendingMarketFactory.MarketParams memory marketParams = CurveLendingMarketFactory.MarketParams({
            irm: Common.MORPHO_ADAPTIVE_CURVE_IRM,
            lltv: lltv,
            initialSupply: 10 ** IERC20Metadata(Common.USDC).decimals()
        });

        // Setup the unified oracle parameters
        CurveLendingMarketFactory.OracleParams memory oracleParams = CurveLendingMarketFactory.OracleParams({
            loanAsset: Common.USDC,
            loanAssetFeed: Common.CHAINLINK_USDC_USD_PRICE_FEED,
            loanAssetFeedHeartbeat: 86_400,
            chainlinkFeeds: chainlinkFeeds,
            chainlinkFeedHeartbeats: chainlinkFeedHeartbeats
        });
        vm.label(Common.CHAINLINK_USDC_USD_PRICE_FEED, "USDC/USD Chainlink Feed");

        // Deposit some Curve LP tokens into the reward vault
        deposit(rewardVault, deployer, position.baseAmount);
        assertEq(rewardVault.balanceOf(deployer), position.baseAmount);

        // Deal $1 of USDC (loan asset) to the user
        address loanAsset = Common.USDC;
        {
            uint256 loanInitialBalance = 10 ** IERC20Metadata(loanAsset).decimals();
            deal(loanAsset, deployer, loanInitialBalance);

            // Approve the curve lending factory to spend the USDC
            vm.prank(deployer);
            IERC20(loanAsset).approve(address(curveLendingMarketFactory), loanInitialBalance);

            // Approve the curve lending factory to spend the reward vault shares
            vm.prank(deployer);
            rewardVault.approve(address(curveLendingMarketFactory), position.baseAmount);
        }

        // Deploy the collateral token and set the owner to the lending market factory (needed to initialize it)
        IStrategyWrapper collateral =
            new StrategyWrapper(rewardVault, address(MORPHO), address(curveLendingMarketFactory));

        // Deploy the market
        address pool = rewardVault.asset();
        vm.prank(deployer);
        (,, bytes memory data) = curveLendingMarketFactory.deploy(
            collateral, pool, oracleType, oracleParams, marketParams, morphoMarketFactory
        );

        // Verify loan asset balance after pre-seeding (should have 90% of initial balance left)
        assertEq(
            IERC20(loanAsset).balanceOf(deployer),
            uint256(9 * 10 ** IERC20Metadata(loanAsset).decimals()) / 10,
            "Account's loan asset balance after pre-seeding"
        );

        // Verify market state
        MorphoId marketID = abi.decode(data, (MorphoId));
        {
            MorphoPosition memory deployerMorphoPosition = MORPHO.position(marketID, deployer);
            MorphoPosition memory factoryMorphoPosition = MORPHO.position(marketID, address(curveLendingMarketFactory));
            MorphoMarketState memory market = MORPHO.market(marketID);

            assertEq(market.lastUpdate, block.timestamp, "Last update");
            assertEq(market.totalSupplyAssets, 10 ** IERC20Metadata(loanAsset).decimals(), "Total supply assets");
            assertEq(
                market.totalBorrowAssets, (10 ** IERC20Metadata(loanAsset).decimals() * 9) / 10, "Total borrow assets"
            );
            assertGt(market.totalSupplyShares, 0, "Total supply shares");
            assertApproxEqRel(
                market.totalSupplyShares - market.totalBorrowShares,
                market.totalSupplyShares / 10,
                1e15, // 0.1%
                "90% of total supply shares borrowed"
            );

            // Verify the positions are as expected
            assertEq(market.totalBorrowShares, factoryMorphoPosition.borrowShares, "Total borrow shares");
            assertEq(market.totalSupplyShares, deployerMorphoPosition.supplyShares, "Total supply shares");
            assertEq(MORPHO.isAuthorized(address(curveLendingMarketFactory), deployer), true);
        }
    }
}
