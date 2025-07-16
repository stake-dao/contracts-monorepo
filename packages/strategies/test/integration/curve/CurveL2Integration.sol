// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {CurveFactory} from "src/integrations/curve/L2/CurveFactory.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {CurveStrategy} from "src/integrations/curve/L2/CurveStrategy.sol";
import {L2ConvexSidecar} from "src/integrations/curve/L2/L2ConvexSidecar.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {L2ConvexSidecarFactory} from "src/integrations/curve/L2/L2ConvexSidecarFactory.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

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
            new CurveStrategy({
                _registry: address(protocolController),
                _locker: config.base.locker,
                _gateway: address(gateway)
            })
        );

        /// 3. Check if the strategy is only boost.
        if (config.convex.isOnlyBoost) {
            /// 3a. Deploy the Convex Sidecar implementation.
            sidecarImplementation = address(
                new L2ConvexSidecar({
                    _accountant: address(accountant),
                    _protocolController: address(protocolController),
                    _cvx: config.convex.cvx,
                    _booster: config.convex.booster
                })
            );

            /// 3b. Deploy the Convex Sidecar factory.
            sidecarFactory = address(
                new L2ConvexSidecarFactory({
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
            new CurveFactory(
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

    /// @notice Override to properly simulate extra rewards for L2 Curve gauges
    function _simulateExtraRewardForToken(
        RewardVault vault,
        address gauge,
        address token,
        uint256 amount
    ) internal override {
        // For L2 Curve gauges, we need to properly set up the reward distribution
        address rewardReceiver = protocolController.rewardReceiver(gauge);
        
        // Try to add the reward token to the gauge using actual gauge functions
        // First check if we can call add_reward (some gauges have this function)
        try ILiquidityGauge(gauge).add_reward(token, rewardReceiver) {
            // Successfully added the reward token
        } catch {
            // If add_reward doesn't exist or fails, try set_reward_distributor
            try ILiquidityGauge(gauge).set_reward_distributor(token, rewardReceiver) {
                // Successfully set the distributor
            } catch {
                // If neither work, we'll need to be the admin/owner or mock the distributor
                // Let's mock being able to set the distributor
                vm.mockCall(
                    gauge,
                    abi.encodeWithSelector(ILiquidityGauge.admin.selector),
                    abi.encode(address(this))
                );
                
                // Now try to set ourselves as distributor temporarily
                try ILiquidityGauge(gauge).set_reward_distributor(token, address(this)) {} catch {}
            }
        }
        
        // Now deposit the reward tokens to the gauge
        deal(token, address(this), amount);
        IERC20(token).approve(gauge, amount);
        
        try ILiquidityGauge(gauge).deposit_reward_token(token, amount) {
            // Successfully deposited rewards
        } catch {
            // If deposit_reward_token doesn't work, transfer directly and mock the reward data
            IERC20(token).transfer(gauge, amount);
            
            // Mock the reward data to show active distribution
            uint256 rate = amount / 7 days;
            uint256 periodFinish = block.timestamp + 7 days;
            
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(ILiquidityGauge.reward_data.selector, token),
                abi.encode(
                    token,           // token
                    rewardReceiver,  // distributor
                    periodFinish,    // period_finish
                    rate,            // rate
                    block.timestamp, // last_update
                    0                // integral
                )
            );
        }
        
        // Ensure the reward receiver can claim by mocking claimable amount
        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.claimable_reward.selector, rewardReceiver, token),
            abi.encode(amount)
        );
        
        // When claim_rewards is called, ensure tokens are transferred
        // We'll mint directly to receiver to simulate the claim
        // Use deal instead of pranking to avoid prank conflicts
        deal(token, rewardReceiver, IERC20(token).balanceOf(rewardReceiver) + amount);
        
        // If there's a Convex sidecar, also set up CVX rewards properly
        if (config.convex.isOnlyBoost && token == config.convex.cvx && sidecarFactory != address(0)) {
            address sidecar = L2ConvexSidecarFactory(sidecarFactory).sidecar(gauge);
            if (sidecar != address(0)) {
                address baseRewardPool = address(L2ConvexSidecar(sidecar).baseRewardPool());
                deal(token, baseRewardPool, IERC20(token).balanceOf(baseRewardPool) + amount);
            }
        }
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
        
        // Try to add reward tokens using gauge functions if possible
        // First mock ourselves as admin to add rewards
        address originalAdmin;
        try ILiquidityGauge(gauge).admin() returns (address admin) {
            originalAdmin = admin;
        } catch {
            originalAdmin = address(0);
        }
        
        // Mock admin to be this contract
        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.admin.selector),
            abi.encode(address(this))
        );
        
        // Try to add rewards through gauge functions
        for (uint256 i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];
            address distributor = makeAddr(string.concat("Distributor", vm.toString(i)));
            
            // Try add_reward first (avoid nested pranks)
            try ILiquidityGauge(gauge).add_reward(token, distributor) {
                // Success - reward added
            } catch {
                // If that fails, we'll mock the reward data
            }
        }
        
        // Now mock the reward_tokens and reward_data for factory discovery
        for (uint256 i = 0; i < extraTokens.length; i++) {
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(ILiquidityGauge.reward_tokens.selector, i),
                abi.encode(extraTokens[i])
            );
            
            // Mock active reward period so factory adds them
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(ILiquidityGauge.reward_data.selector, extraTokens[i]),
                abi.encode(
                    extraTokens[i],              // token
                    makeAddr(string.concat("Distributor", vm.toString(i))),  // distributor
                    block.timestamp + 1 days,    // period_finish (active so factory adds it)
                    1e18,                        // rate
                    block.timestamp,             // last_update
                    0                            // integral
                )
            );
        }
        
        // Mock empty token for index 2 to signal end of list
        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.reward_tokens.selector, 2),
            abi.encode(address(0))
        );
        
        // Restore original admin if needed
        if (originalAdmin != address(0)) {
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(ILiquidityGauge.admin.selector),
                abi.encode(originalAdmin)
            );
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
}
