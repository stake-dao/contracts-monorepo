// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactoryL2} from "src/integrations/curve/L2/CurveFactoryL2.sol";
import {ILiquidityGauge, IL2LiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {CurveStrategyL2} from "src/integrations/curve/L2/CurveStrategyL2.sol";
import {ConvexSidecarL2} from "src/integrations/curve/L2/ConvexSidecarL2.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ConvexSidecarFactoryL2} from "src/integrations/curve/L2/ConvexSidecarFactoryL2.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "test/integration/BaseIntegrationTest.sol";

/// @title CurveIntegration - L2 Curve Integration Test
/// @notice Integration test for Curve protocol on L2 with Convex.
abstract contract CurveL2Integration is BaseIntegrationTest {
    /// @notice Base configuration for the test.
    struct BaseConfig {
        string chain;
        bytes4 protocolId;
        uint256 blockNumber;
        address locker;
        address rewardToken;
        IStrategy.HarvestPolicy harvestPolicy;
        address minter;
        address boostProvider;
        address oldStrategy;
        address gaugeController;
    }

    /// @notice Convex-specific configuration.
    struct ConvexConfig {
        bool isOnlyBoost;
        address cvx;
        address convexBoostHolder;
        address booster;
    }

    /// @notice Combined configuration for the test.
    struct Config {
        BaseConfig base;
        ConvexConfig convex;
    }

    /// @notice The configuration for the test.
    Config public config;

    /// @notice Mapping to store extra reward tokens for each gauge
    mapping(address => address[]) public gaugeExtraTokens;

    constructor(Config memory _config) {
        config = _config;
    }

    function setUp()
        public
        virtual
        doSetup(
            config.base.chain,
            config.base.blockNumber,
            config.base.rewardToken,
            config.base.locker,
            config.base.protocolId,
            config.base.harvestPolicy
        )
    {
        /// 1. Get the gauges.
        gauges = getGauges();

        /// 2. Deploy the Curve Strategy contract.
        strategy = address(
            new CurveStrategyL2({
                _registry: address(protocolController),
                _locker: config.base.locker,
                _gateway: address(gateway)
            })
        );

        /// 3. Check if the strategy is only boost.
        if (config.convex.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                new ConvexSidecarL2({
                    _accountant: address(accountant),
                    _protocolController: address(protocolController),
                    _cvx: config.convex.cvx,
                    _booster: config.convex.booster
                })
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                new ConvexSidecarFactoryL2({
                    _implementation: address(sidecarImplementation),
                    _protocolController: address(protocolController),
                    _booster: config.convex.booster
                })
            );

            /// 3c. Deploy the OnlyBoostAllocator contract.
            allocator = new OnlyBoostAllocator({
                _locker: config.base.locker,
                _gateway: address(gateway),
                _convexSidecarFactory: sidecarFactory,
                _boostProvider: config.base.boostProvider,
                _convexBoostHolder: config.convex.convexBoostHolder
            });
        }

        factory = address(
            new CurveFactoryL2(
                admin,
                address(protocolController),
                address(rewardVaultImplementation),
                address(rewardReceiverImplementation),
                config.base.locker,
                address(gateway),
                config.convex.booster,
                sidecarFactory
            )
        );

        _clearLockerBalances();
    }

    /// @notice Mock extra reward tokens on gauges before vault deployment
    function _setupGaugeExtraRewards(address gauge) internal virtual {
        // For Base and Fraxtal, we'll set up some common reward tokens
        // This will be called before vault deployment so the factory can discover them

        // Deploy mock ERC20 tokens for extra rewards
        address[] memory extraTokens = new address[](2);
        extraTokens[0] = _deployMockERC20("Balancer", "BAL", 18);
        extraTokens[1] = _deployMockERC20("Lido", "LDO", 18);

        // Store tokens for later use
        gaugeExtraTokens[gauge] = extraTokens;

        // On L2s, the factory owner can add rewards
        address gaugeFactory = ILiquidityGauge(gauge).factory();
        address factoryOwner = Ownable(gaugeFactory).owner();

        // Add rewards through gauge functions
        for (uint256 i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];
            address distributor = makeAddr(string.concat("Distributor", vm.toString(i)));

            vm.prank(factoryOwner);
            ILiquidityGauge(gauge).add_reward(token, distributor);

            // Deposit some initial rewards
            uint256 rewardAmount = 1000e18;
            deal(token, distributor, rewardAmount);

            vm.startPrank(distributor);
            IERC20(token).approve(gauge, type(uint256).max);
            ILiquidityGauge(gauge).deposit_reward_token(token, rewardAmount);
            vm.stopPrank();
        }
    }

    /// @notice Deploy a mock ERC20 token for testing
    function _deployMockERC20(string memory name, string memory symbol, uint8 decimals) internal returns (address) {
        // Deploy a minimal ERC20 mock
        ERC20Mock token = new ERC20Mock(name, symbol, decimals);
        return address(token);
    }

    function _clearLockerBalances() internal {
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 balance = ILiquidityGauge(gauges[i]).balanceOf(config.base.locker);
            if (balance == 0) continue;

            address lpToken = ILiquidityGauge(gauges[i]).lp_token();
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Withdraw from gauge
            bytes memory data = abi.encodeWithSignature("withdraw(uint256)", balance);
            SafeLibrary.execOnLocker(payable(gateway), config.base.locker, gauges[i], data, signatures);

            // Transfer to burn address
            data = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            SafeLibrary.execOnLocker(payable(gateway), config.base.locker, lpToken, data, signatures);
        }
    }

    /// @notice Test that new reward tokens added to gauge after vault creation are automatically synced during harvest
    function test_automatic_sync_new_reward_tokens() public {
        // Deploy vaults normally (with initial extra rewards from _setupGaugeExtraRewards)
        (rewardVaults, rewardReceivers) = deployRewardVaults();

        RewardVault vault = rewardVaults[0];
        address gauge = vault.gauge();

        // Verify we have the initial extra rewards from _setupGaugeExtraRewards
        address[] memory initialTokens = vault.getRewardTokens();
        uint256 initialTokenCount = initialTokens.length;
        assertGe(initialTokenCount, 2, "Should have at least 2 initial extra reward tokens");

        // User deposits
        address user = makeAddr("user");
        deposit(vault, user, 100e18);

        // Add a THIRD reward token to the gauge (not included in initial setup)
        address newRewardToken = _deployMockERC20("ThirdReward", "THIRD", 18);

        // On L2s, the factory owner or gauge manager can add rewards
        address gaugeFactory = ILiquidityGauge(gauge).factory();
        address factoryOwner = Ownable(gaugeFactory).owner();

        vm.startPrank(factoryOwner);

        uint256 count = ILiquidityGauge(gauge).reward_count(); // Trigger any internal state updates

        // Add the new reward token with reward receiver as distributor
        ILiquidityGauge(gauge).add_reward(newRewardToken, factoryOwner);

        // Now deposit reward tokens as the distributor (reward receiver)
        uint256 rewardAmount = 1000e18;
        deal(newRewardToken, factoryOwner, rewardAmount);

        IERC20(newRewardToken).approve(gauge, type(uint256).max);
        ILiquidityGauge(gauge).deposit_reward_token(newRewardToken, rewardAmount);

        vm.stopPrank();

        assertEq(count + 1, ILiquidityGauge(gauge).reward_count(), "Should have 1 more reward token now");

        // Harvest - this should sync the new token
        harvest();

        address[] memory updateTokens = vault.getRewardTokens();
        assertGe(updateTokens.length, 3, "Should now have 3 reward tokens");

        // Check if the new token was actually added
        bool tokenFound = false;
        for (uint256 i = 0; i < updateTokens.length; i++) {
            if (updateTokens[i] == newRewardToken) {
                tokenFound = true;
                break;
            }
        }
        assertTrue(tokenFound, "New token should be in vault");

        // Skip more time to accumulate rewards
        skip(1 days);

        // Harvest again to trigger reward distribution
        harvest();

        skip(1 days);

        // Verify rewards were distributed to vault
        assertGt(
            IERC20(newRewardToken).balanceOf(address(vault)), 0, "Vault should have received the new reward tokens"
        );

        // User can claim the new rewards
        vm.prank(user);
        address[] memory claimTokens = new address[](1);
        claimTokens[0] = newRewardToken;
        vault.claim(claimTokens, user);

        assertGt(IERC20(newRewardToken).balanceOf(user), 0, "User should have claimed the new rewards");
    }
}
