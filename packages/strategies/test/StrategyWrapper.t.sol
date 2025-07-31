// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import {CurveMainnetIntegrationTest} from "test/integration/curve/mainnet/CurveMainnetIntegration.t.sol";
import {RewardVault} from "src/RewardVault.sol";
import {StrategyWrapper, IStrategyWrapper} from "src/wrappers/StrategyWrapper.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IMorpho, MarketParams, Market, Position, Id} from "shared/src/morpho/IMorpho.sol";
import {CurveLendingMarketFactory} from "src/integrations/curve/lending/CurveLendingMarketFactory.sol";
import {MorphoMarketFactory} from "src/integrations/morpho/MorphoMarketFactory.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {MorphoMath} from "shared/src/morpho/MorphoMath.sol";
import {Test} from "forge-std/src/Test.sol";
import {MarketParamsLib} from "shared/src/morpho/MarketParamsLib.sol";

contract StrategyWrapperIntegrationTest is CurveMainnetIntegrationTest {
    using MorphoMath for uint256;

    StrategyWrapper internal wrapper;
    IMorpho internal constant morpho = IMorpho(Common.MORPHO_BLUE);
    CurveLendingMarketFactory internal curveLendingMarketFactory;
    MorphoMarketFactory internal morphoMarketFactory;

    AccountPosition private fuzzedPosition;
    uint256 private fuzzedReward;
    bytes32 private lendingMarketId;

    constructor() CurveMainnetIntegrationTest() {}

    // @dev Only fuzz a single account position
    function MAX_ACCOUNT_POSITIONS() public virtual override returns (uint256) {
        return 1;
    }

    // @dev Only use one Curve pool for our test
    function poolIds() public pure override returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](1);
        _poolIds[0] = 426; // USDC/USDT (0x4f493b7de8aac7d55f71853688b1f7c8f0243c85)
        return _poolIds;
    }

    function setUp() public override {
        super.setUp();

        // 1. Fuzz new account positions and rewards
        (AccountPosition[] memory _positions, uint256[] memory _rewards) = _generateAccountPositionsAndRewards();
        fuzzedPosition = _positions[0];
        fuzzedReward = _rewards[0];

        // 2. Deploy new reward vaults
        (RewardVault[] memory vaults,) = deployRewardVaults();
        address rewardVault = address(vaults[0]);
        vm.label(rewardVault, "RewardVault");

        // 3. Deploy the lending market factory
        curveLendingMarketFactory =
            new CurveLendingMarketFactory(address(protocolController), CurveProtocol.META_REGISTRY);
        vm.label(address(factory), "CurveLendingMarketFactory");

        // 4. Deploy the Morpho Market Factory
        morphoMarketFactory = new MorphoMarketFactory(address(morpho));
        vm.label(address(morphoMarketFactory), "MorphoMarketFactory");

        // 5. Deploy the collateral token and set the owner to the lending market factory (needed to initialize it)
        IStrategyWrapper _wrapper =
            new StrategyWrapper(IRewardVault(rewardVault), address(morpho), address(curveLendingMarketFactory));

        // 5. Deploy the lending market
        CurveLendingMarketFactory.MarketParams memory marketParams = CurveLendingMarketFactory.MarketParams({
            irm: Common.MORPHO_ADAPTIVE_CURVE_IRM,
            lltv: 945 * 1e15,
            initialSupply: 0
        });
        address[] memory chainlinkFeeds = new address[](2);
        chainlinkFeeds[0] = Common.CHAINLINK_USDC_USD_PRICE_FEED;
        chainlinkFeeds[1] = Common.CHAINLINK_USDT_USD_PRICE_FEED;
        uint256[] memory chainlinkFeedHeartbeats = new uint256[](2);
        chainlinkFeedHeartbeats[0] = 1 days;
        chainlinkFeedHeartbeats[1] = 1 days;
        CurveLendingMarketFactory.OracleParams memory oracleParams = CurveLendingMarketFactory.OracleParams({
            loanAsset: Common.USDC,
            loanAssetFeed: Common.CHAINLINK_USDC_USD_PRICE_FEED,
            loanAssetFeedHeartbeat: 86_400,
            chainlinkFeeds: chainlinkFeeds,
            chainlinkFeedHeartbeats: chainlinkFeedHeartbeats
        });
        (, IOracle _oracle, bytes memory data) = curveLendingMarketFactory.deploy(
            _wrapper, CurveLendingMarketFactory.OracleType.STABLESWAP, oracleParams, marketParams, morphoMarketFactory
        );
        wrapper = StrategyWrapper(address(_wrapper));
        vm.label(address(_wrapper), "StrategyWrapper");
        vm.label(address(_oracle), "Oracle");
        vm.label(address(morpho), "Morpho");

        lendingMarketId = abi.decode(data, (bytes32));
        MarketParams memory market = morpho.idToMarketParams(Id.wrap(wrapper.lendingMarketId()));

        // 6. Supply some liquidity to the market
        address supplier = makeAddr("supplier");
        uint256 supplyAmount = 100_000e6;
        deal(market.loanToken, supplier, supplyAmount);
        vm.startPrank(supplier);
        IERC20(market.loanToken).approve(address(morpho), supplyAmount);
        morpho.supply({marketParams: market, assets: supplyAmount, shares: 0, onBehalf: supplier, data: hex""});
        vm.stopPrank();
    }

    // @dev Test the complete protocol lifecycle with one account interacting directly with the protocol and one interacting with the morpho wrapper
    function test_complete_protocol_lifecycle() public override {
        AccountPosition memory position = fuzzedPosition;
        uint256 rewardAmount = fuzzedReward;
        address directUser = position.account;
        vm.label(directUser, "DirectUser");
        address wrapperUser = makeAddr("WrapperUser");
        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));

        // Add an extra reward token to the reward vault
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        // 1. Both users deposit to the vault (wrapped tokens auto-supplied to Morpho)
        deposit(rewardVault, directUser, position.baseAmount);
        _depositIntoWrapper(rewardVault, wrapperUser, position.baseAmount);

        // Make sure the balances post-deposit are correct
        assertEq(rewardVault.balanceOf(directUser), position.baseAmount, "Direct user: vault balance after deposit");
        assertEq(rewardVault.balanceOf(wrapperUser), 0, "Wrapper user: vault balance after wrapping");
        assertEq(rewardVault.balanceOf(address(wrapper)), position.baseAmount, "Wrapper holds vault shares");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after wrapping");
        assertEq(wrapper.balanceOf(address(morpho)), position.baseAmount, "Wrapper user: Morpho balance after wrapping");

        // 2. Deposit some extra reward token into the reward vault
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);

        // 3. Simulate rewards and harvest
        simulateRewards(rewardVault, rewardAmount);
        deal(address(rewardToken), address(accountant), rewardAmount);
        skip(2 days);
        harvest();

        // 4. Both users claim rewards
        claim(rewardVault, directUser);
        _claimFromWrapper(wrapperUser);
        _claimFromWrapper(address(morpho)); // in case Morpho is malicious and tried to claim rewards

        // Make sure the claimed rewards are the same
        assertNotEq(_balanceOf(rewardToken, directUser), 0, "Direct user: should have claimed rewards");
        assertNotEq(_balanceOf(rewardToken, wrapperUser), 0, "Wrapper user: should have claimed rewards");
        assertEq(_balanceOf(rewardToken, address(morpho)), 0, "Morpho: should have no claimed rewards"); // morpho claimed nothing
        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e16, // 1% (rounding)
            "Claimed rewards should match"
        );

        // 5. Both users deposit more
        deposit(rewardVault, directUser, position.additionalAmount);
        _depositIntoWrapper(rewardVault, wrapperUser, position.additionalAmount);

        uint256 expected = position.baseAmount + position.additionalAmount;
        assertEq(rewardVault.balanceOf(directUser), expected, "Direct user: vault balance after additional deposit");
        assertEq(rewardVault.balanceOf(wrapperUser), 0, "Wrapper user: vault balance after wrapping again");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after wrapping");
        assertEq(wrapper.balanceOf(address(morpho)), expected, "Wrapper user: Morpho balance after wrapping");

        // 6. Both users withdraw partially
        withdraw(rewardVault, directUser, position.partialWithdrawAmount);
        _withdrawFromWrapper(wrapperUser, position.partialWithdrawAmount);

        expected = expected - position.partialWithdrawAmount;
        assertEq(rewardVault.balanceOf(directUser), expected, "Direct user: vault balance after partial withdraw");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after partial withdraw");
        assertEq(wrapper.balanceOf(address(morpho)), expected, "Wrapper user: Morpho balance after partial withdraw");
        assertEq(rewardVault.balanceOf(address(wrapper)), expected, "Wrapper holds vault shares after partial withdraw");

        // 7. Simulate more rewards and harvest
        simulateRewards(rewardVault, rewardAmount / 2);
        deal(address(rewardToken), address(accountant), rewardAmount / 2);
        skip(1 days);
        harvest();

        // 8. Both users claim again
        claim(rewardVault, directUser);
        _claimFromWrapper(wrapperUser);

        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e15, // 0.1% (rounding)
            "Claimed rewards after more rewards should match"
        );

        // 9. Both users withdraw all
        _withdrawFromWrapper(wrapperUser, rewardVault.balanceOf(directUser));
        withdraw(rewardVault, directUser, rewardVault.balanceOf(directUser));

        assertEq(rewardVault.balanceOf(directUser), 0, "Direct user: vault balance after final withdraw");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after final withdraw");
        assertEq(wrapper.balanceOf(address(morpho)), 0, "Wrapper user: Morpho balance after final withdraw");
        assertEq(rewardVault.balanceOf(address(wrapper)), 0, "Wrapper holds no vault shares after final withdraw");
        assertEq(
            rewardVault.balanceOf(wrapperUser),
            expected + position.partialWithdrawAmount,
            "Wrapper user should have all vault shares after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(directUser),
            position.baseAmount + position.additionalAmount,
            "Direct user: should get back of all deposited assets after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            0,
            "Wrapper user: should not get back of any deposited assets after final withdraw as still in the vault"
        );
        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e15, // 0.1%
            "Final claimed rewards should match between direct and wrapper user"
        );

        // 10. Wrapped user withdraws from the vault
        withdraw(rewardVault, wrapperUser, rewardVault.balanceOf(wrapperUser));
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            position.baseAmount + position.additionalAmount,
            "Wrapper user: should get back of all deposited assets after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            IERC20(rewardVault.asset()).balanceOf(directUser),
            "Both users should have the same final balance of asset token"
        );

        // 11. Claim the extra reward tokens with the direct user
        address[] memory tokens = new address[](1);
        tokens[0] = Common.WETH;
        vm.prank(directUser);
        rewardVault.claim(tokens, directUser);

        // 12. Make sure both users received the same amount of extra rewards
        uint256 wrapperUserRealExtraRewardBalance = IERC20(Common.WETH).balanceOf(wrapperUser);
        uint256 directUserRealExtraRewardBalance = IERC20(Common.WETH).balanceOf(directUser);
        assertApproxEqRel(
            wrapperUserRealExtraRewardBalance,
            directUserRealExtraRewardBalance,
            1e16, // 0.1% tolerance
            "Direct user: should have the expected extra reward token balance"
        );

        // 13. Make sure the wrapper user cannot claim extra rewards unlocked after he left the wrapper contract
        skip(10 days);
        _claimExtraRewardsFromWrapper(wrapperUser);
        assertEq(IERC20(Common.WETH).balanceOf(wrapperUser), wrapperUserRealExtraRewardBalance);
    }

    /// @notice Test that re-depositing into the wrapper automatically claims pending rewards to prevent loss
    function test_reDepositAutoClaimsRewards() external {
        ///////////////////////////////////////////////////////////////
        // --- SETUP
        ///////////////////////////////////////////////////////////////

        AccountPosition memory position = fuzzedPosition;
        address user = position.account;
        uint256 initialDeposit = position.baseAmount;
        uint256 additionalDeposit = position.additionalAmount;
        vm.label(user, "User");
        uint256 rewardAmount = fuzzedReward;

        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));

        // Add extra reward token
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        ///////////////////////////////////////////////////////////////
        // --- TEST EXECUTION
        ///////////////////////////////////////////////////////////////

        // 1. User makes initial deposit into wrapper
        _depositIntoWrapper(rewardVault, user, initialDeposit);
        assertEq(wrapper.balanceOf(user), 0, "Initial deposit should succeed");
        assertEq(wrapper.balanceOf(address(morpho)), initialDeposit, "Initial deposit should succeed");

        // 2. Simulate rewards accumulation
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);

        simulateRewards(rewardVault, rewardAmount);
        deal(address(rewardToken), address(accountant), rewardAmount);
        skip(2 days);
        harvest();

        // 3. Record balances before re-deposit
        uint256 mainTokenBalanceBefore = _balanceOf(rewardToken, user);
        uint256 extraTokenBalanceBefore = IERC20(Common.WETH).balanceOf(user);

        // 4. User makes additional deposit (this should auto-claim pending rewards)
        _depositIntoWrapper(rewardVault, user, additionalDeposit);

        // 5. Verify rewards were automatically claimed during re-deposit
        uint256 mainTokenBalanceAfter = _balanceOf(rewardToken, user);
        uint256 extraTokenBalanceAfter = IERC20(Common.WETH).balanceOf(user);

        // 6. Verify substantial amounts were claimed (not just dust)
        assertGt(mainTokenBalanceAfter, mainTokenBalanceBefore, "Main rewards should be auto-claimed");
        assertGt(extraTokenBalanceAfter, extraTokenBalanceBefore, "Extra rewards should be auto-claimed");
        assertGt(mainTokenBalanceAfter - mainTokenBalanceBefore, 1e18, "Significant main rewards claimed");
        assertGt(extraTokenBalanceAfter - extraTokenBalanceBefore, 1e16, "Significant extra rewards claimed");
    }

    // // @dev Test the extra rewards distribution is fair between users (second user gets 0)
    function test_extraRewardsFairDistribution() public {
        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));
        address firstUser = makeAddr("firstUser");
        address secondUser = makeAddr("secondUser");

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        // 1. First user deposits to the vault
        _depositIntoWrapper(rewardVault, firstUser, 1e18);

        // 2. Deposit some extra reward token into the reward vault
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);

        // 3. Second user deposits to the vault after 1 week
        skip(7 days);
        _depositIntoWrapper(rewardVault, secondUser, 100_000e18);

        // 4. Second user withdraws immediately after depositing
        _withdrawFromWrapper(secondUser, 100_000e18);

        // 5. First user claims extra rewards
        _claimExtraRewardsFromWrapper(firstUser);

        // 6. Ensure the second user received nothing. The first user received all the extra rewards
        assertApproxEqRel(
            IERC20(Common.WETH).balanceOf(firstUser),
            extraRewardAmount,
            1e15, // 0.1% (rounding)
            "First user: should have the expected extra reward token balance"
        );
        assertApproxEqRel(
            IERC20(Common.WETH).balanceOf(secondUser),
            0,
            1e15, // 0.1% (rounding)
            "Second user: should have no extra reward token balance"
        );
    }

    function test_liquidation() external {
        AccountPosition memory position = fuzzedPosition;
        uint256 rewardAmount = fuzzedReward;
        address user = position.account;
        vm.label(user, "User");
        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));

        // Add an extra reward token to the reward vault
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        // 1. User deposits
        _depositIntoWrapper(rewardVault, user, position.baseAmount);

        // 2. User borrow
        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(wrapper.lendingMarketId()));
        Position memory _position = morpho.position(Id.wrap(wrapper.lendingMarketId()), user);
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 maxBorrow = uint256(_position.collateral).mulDivDown(collateralPrice, 1e36).wMulDown(marketParams.lltv);
        uint256 borrowAmount = maxBorrow * 9 / 10;

        vm.prank(user);
        morpho.borrow(marketParams, borrowAmount, 0, user, user);

        _position = morpho.position(Id.wrap(wrapper.lendingMarketId()), user);
        assertEq(IERC20(marketParams.loanToken).balanceOf(user), borrowAmount);

        // 3. Inject some extra rewards
        uint128 extraRewardAmount = 1e20;
        {
            deal(Common.WETH, address(this), extraRewardAmount);
            IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
            rewardVault.depositRewards(Common.WETH, extraRewardAmount);
            simulateRewards(rewardVault, rewardAmount);
            deal(address(rewardToken), address(accountant), rewardAmount);
        }

        //  4. Wait a week and harvest
        skip(7 days);
        harvest(); // ??

        address liquidator = address(new MockLiquidator());
        {
            // Check balance states
            assertEq(IERC20(marketParams.collateralToken).balanceOf(address(morpho)), position.baseAmount);
            assertEq(IERC20(marketParams.collateralToken).balanceOf(address(user)), 0);
            assertEq(IERC20(marketParams.collateralToken).balanceOf(address(liquidator)), 0);
            assertEq(IERC20(marketParams.collateralToken).totalSupply(), position.baseAmount);
            assertEq(IERC20(marketParams.loanToken).balanceOf(user), borrowAmount);
            assertEq(IERC20(marketParams.loanToken).balanceOf(liquidator), 0);
            assertEq(IERC20(wrapper.REWARD_VAULT()).totalSupply(), IERC20(marketParams.collateralToken).totalSupply());

            address[] memory rewardTokens = rewardVault.getRewardTokens();
            for (uint256 i; i < rewardTokens.length; i++) {
                assertEq(IERC20(rewardTokens[i]).balanceOf(user), 0);
                assertEq(IERC20(rewardTokens[i]).balanceOf(liquidator), 0);
            }

            assertEq(IERC20(CurveProtocol.CRV).balanceOf(user), 0);
            assertEq(IERC20(CurveProtocol.CRV).balanceOf(liquidator), 0);
        }

        uint256 userMainRewards = wrapper.getPendingRewards(user);
        uint256 userExtraReward = wrapper.getPendingExtraRewards(user, Common.WETH);
        {
            assertGt(userMainRewards, 0, "User: should have some main rewards");
            assertGt(userExtraReward, 0, "User: should have some extra rewards");
        }

        // 5. Liquidate user
        vm.mockCall(marketParams.oracle, abi.encodeWithSelector(IOracle.price.selector), abi.encode(0));
        bytes memory data = abi.encode(address(wrapper), liquidator, user, _position.collateral);
        vm.prank(liquidator);
        morpho.liquidate(marketParams, user, _position.collateral, 0, data);

        // 6. Check the liquidated user received all his due rewards
        {
            assertEq(IERC20(CurveProtocol.CRV).balanceOf(fuzzedPosition.account), userMainRewards);
            assertEq(IERC20(CurveProtocol.CRV).balanceOf(liquidator), 0);

            assertEq(IERC20(Common.WETH).balanceOf(fuzzedPosition.account), userExtraReward);
            assertEq(IERC20(Common.WETH).balanceOf(liquidator), 0);
        }

        // 7. Check final balances
        assertEq(IERC20(marketParams.collateralToken).balanceOf(address(morpho)), 0);
        assertEq(IERC20(marketParams.collateralToken).balanceOf(address(fuzzedPosition.account)), 0);
        assertEq(IERC20(marketParams.collateralToken).balanceOf(address(liquidator)), 0);
        assertEq(IERC20(marketParams.collateralToken).totalSupply(), 0);
        assertEq(IERC20(marketParams.loanToken).balanceOf(fuzzedPosition.account), borrowAmount);
        assertEq(IERC20(marketParams.loanToken).balanceOf(liquidator), 0);
        assertEq(
            IERC20(wrapper.REWARD_VAULT()).totalSupply(), IERC20(wrapper.REWARD_VAULT()).balanceOf(address(liquidator))
        );
        assertGt(IERC20(wrapper.REWARD_VAULT()).totalSupply(), IERC20(marketParams.collateralToken).totalSupply());
    }

    function test_withdrawToReceiver(address receiver) external {
        vm.assume(receiver != address(0) && receiver != address(morpho));
        AccountPosition memory position = fuzzedPosition;
        uint256 rewardAmount = fuzzedReward;

        address user = position.account;
        vm.label(user, "user");

        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));

        // 1. User deposits
        _depositIntoWrapper(rewardVault, user, position.baseAmount);

        // 2. We deploy another lending market that uses the same collateral token
        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(wrapper.lendingMarketId()));
        uint256 oldlltv = marketParams.lltv; // store the old LLTV to quickly get back to the legit market
        uint256 maliciouslltv = 965 * 1e15;
        marketParams.lltv = maliciouslltv; // we change the LLTV to have a different hash
        morpho.createMarket(marketParams);
        Id maliciousLendingMarketId = MarketParamsLib.id(marketParams);

        // 3. Receiver withdraws from Morpho
        marketParams.lltv = oldlltv; // get back to the legit market
        vm.prank(user);
        morpho.withdrawCollateral(marketParams, position.baseAmount, user, receiver);

        // 4. Receiver tries to deposit to the malicious market -- prohibited
        marketParams.lltv = maliciouslltv;
        vm.prank(receiver);
        vm.expectRevert();
        morpho.supplyCollateral(marketParams, position.baseAmount, receiver, "");

        // 5. Receiver tries to deposit back to the legit market -- impossible
        marketParams.lltv = oldlltv;
        vm.prank(receiver);
        vm.expectRevert();
        morpho.supplyCollateral(marketParams, position.baseAmount, receiver, "");

        // 6. Receiver tries to transfer the collateral -- prohibited
        vm.prank(receiver);
        vm.expectRevert();
        IERC20(marketParams.collateralToken).transfer(makeAddr("toto"), position.baseAmount);

        // 7. Receiver tries to withdraw from the wrapper contract -- impossible
        vm.prank(receiver);
        vm.expectRevert();
        wrapper.withdraw();

        // 8. Receiver exit the contract by "liquidating" the original holder
        vm.prank(receiver);
        wrapper.claimLiquidation(receiver, user, position.baseAmount);
        assertEq(wrapper.balanceOf(user), 0);
        assertEq(wrapper.balanceOf(receiver), 0);
        assertEq(wrapper.balanceOf(address(morpho)), 0);
        assertEq(wrapper.REWARD_VAULT().balanceOf(user), 0);
        assertEq(wrapper.REWARD_VAULT().balanceOf(receiver), position.baseAmount);
    }

    function test_depositRestrictions(address _to) external {
        vm.assume(_to != address(0) && _to != address(morpho));

        AccountPosition memory position = fuzzedPosition;
        uint256 rewardAmount = fuzzedReward;

        address user = position.account;
        vm.label(user, "user");

        RewardVault rewardVault = RewardVault(address(wrapper.REWARD_VAULT()));

        // 1. User deposits
        _depositIntoWrapper(rewardVault, user, position.baseAmount);

        // 2. We deploy another lending market that uses the same collateral token
        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(wrapper.lendingMarketId()));
        uint256 oldlltv = marketParams.lltv; // store the old LLTV to quickly get back to the legit market
        uint256 maliciouslltv = 965 * 1e15;
        marketParams.lltv = maliciouslltv; // we change the LLTV to have a different hash
        morpho.createMarket(marketParams);
        Id maliciousLendingMarketId = MarketParamsLib.id(marketParams);

        // 3. User withdraws from Morpho
        marketParams.lltv = oldlltv; // get back to the legit market
        vm.prank(user);
        morpho.withdrawCollateral(marketParams, position.baseAmount, user, user);

        // 4. User tries to deposit to the malicious market -- prohibited
        marketParams.lltv = maliciouslltv;
        vm.prank(user);
        vm.expectRevert();
        morpho.supplyCollateral(marketParams, position.baseAmount, user, "");

        // 5. User tries to deposit back to the legit market -- impossible
        marketParams.lltv = oldlltv;
        vm.prank(user);
        vm.expectRevert();
        morpho.supplyCollateral(marketParams, position.baseAmount, user, "");

        // 6. User tries to transfer the collateral -- prohibited
        vm.prank(user);
        vm.expectRevert();
        IERC20(marketParams.collateralToken).transfer(_to, position.baseAmount);

        // 7. User can withdraw from the wrapper contract
        vm.prank(user);
        wrapper.withdraw();
        assertEq(wrapper.balanceOf(user), 0);
        assertEq(wrapper.REWARD_VAULT().balanceOf(user), position.baseAmount);
        assertEq(wrapper.balanceOf(address(morpho)), 0);
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL UTILS FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _depositIntoWrapper(RewardVault rewardVault, address account, uint256 amount) internal {
        // 1. Mint the shares token by depositing into the reward vault
        deposit(rewardVault, account, amount);

        // 2. Approve the shares token to be spent by the wrapper
        vm.startPrank(account);
        rewardVault.approve(address(wrapper), amount);

        // 3. Deposit the shares token into the wrapper
        wrapper.depositShares();
        vm.stopPrank();
    }

    function _withdrawFromWrapper(address account, uint256 amount) internal {
        vm.startPrank(account);
        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(lendingMarketId));
        morpho.withdrawCollateral(marketParams, amount, account, account);
        wrapper.withdraw(amount);
        vm.stopPrank();
    }

    function _claimFromWrapper(address user) internal {
        vm.prank(user);
        wrapper.claim();
    }

    function _claimExtraRewardsFromWrapper(address user) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = Common.WETH;
        vm.prank(user);
        wrapper.claimExtraRewards(tokens);
    }
}

contract MockLiquidator is Test {
    function onMorphoLiquidate(uint256, bytes memory data) external {
        (address asset, address liquidator, address user, uint256 liquidatedAmount) =
            abi.decode(data, (address, address, address, uint256));
        StrategyWrapper(asset).claimLiquidation(liquidator, user, liquidatedAmount);
    }
}
