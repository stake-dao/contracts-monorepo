// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveIntegration.sol";
import {CurveLocker, CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {OnlyBoostAllocator} from "src/integrations/curve/OnlyBoostAllocator.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";
import {IBaseRewardPool} from "@interfaces/convex/IBaseRewardPool.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {SafeLibrary} from "test/utils/SafeLibrary.sol";

contract CurveMainnetIntegrationTest is CurveIntegration {
    using Math for uint256;

    Config public _config = Config({
        base: BaseConfig({
            chain: "mainnet",
            blockNumber: 22_316_395,
            rewardToken: CurveProtocol.CRV,
            locker: CurveLocker.LOCKER,
            protocolId: bytes4(keccak256("CURVE")),
            harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT,
            minter: CurveProtocol.MINTER,
            boostProvider: CurveProtocol.VE_BOOST,
            gaugeController: CurveProtocol.GAUGE_CONTROLLER,
            oldStrategy: CurveLocker.STRATEGY
        }),
        convex: ConvexConfig({
            isOnlyBoost: true,
            cvx: CurveProtocol.CONVEX_TOKEN,
            convexBoostHolder: CurveProtocol.CONVEX_PROXY,
            booster: CurveProtocol.CONVEX_BOOSTER
        })
    });

    function poolIds() public view virtual returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](7);
        _poolIds[0] = 68;
        _poolIds[1] = 40;
        _poolIds[2] = 437;
        _poolIds[3] = 436;
        _poolIds[4] = 435;
        _poolIds[5] = 434;
        _poolIds[6] = 433;
        return _poolIds;
    }

    // All pool IDs from the old tests
    // uint256[] public poolIds = [68, 40, 437, 436, 435, 434, 433];

    // Mapping to store extra reward tokens for each gauge
    mapping(address => address[]) public gaugeExtraTokens;

    constructor() CurveIntegration(_config) {}

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        // Set up extra rewards for all gauges before vault deployment
        for (uint256 i = 0; i < gauges.length; i++) {
            _setupGaugeExtraRewards(gauges[i]);
        }

        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);

        uint256[] memory _poolIds = poolIds();
        for (uint256 i = 0; i < _poolIds.length; i++) {
            uint256 poolId = _poolIds[i];

            /// Deploy the vault and receiver.
            (address vault, address receiver,) = CurveFactory(factory).create(poolId);

            vaults[i] = RewardVault(vault);
            receivers[i] = RewardReceiver(receiver);
        }
    }

    function getGauges() internal override returns (address[] memory) {
        // Get gauge addresses for all pool IDs
        IBooster booster = IBooster(CurveProtocol.CONVEX_BOOSTER);
        uint256[] memory _poolIds = poolIds();
        address[] memory gauges = new address[](_poolIds.length);

        for (uint256 i = 0; i < _poolIds.length; i++) {
            (,, address gauge,,,) = booster.poolInfo(_poolIds[i]);

            // Mark as shutdown in old strategy
            vm.mockCall(
                CurveLocker.STRATEGY,
                abi.encodeWithSelector(bytes4(keccak256("isShutdown(address)")), gauge),
                abi.encode(true)
            );

            // Mock reward distributor as zero
            vm.mockCall(
                CurveLocker.STRATEGY,
                abi.encodeWithSelector(bytes4(keccak256("rewardDistributors(address)")), gauge),
                abi.encode(address(0))
            );

            gauges[i] = gauge;
        }

        return gauges;
    }

    function simulateRewards(RewardVault vault, uint256 amount) internal override {
        address gauge = vault.gauge();

        // Simply simulate all rewards on the locker
        // The actual distribution will happen based on the allocator's logic
        simulateLockerRewards(gauge, amount);
    }

    /// @notice Override harvest for mainnet to handle extra rewards
    function harvest() internal override {
        // First do the normal harvest
        super.harvest();

        // Then manually claim and distribute extra rewards for mainnet
        for (uint256 i = 0; i < rewardVaults.length; i++) {
            _claimAndDistributeExtraRewards(rewardVaults[i], rewardReceivers[i]);
        }
    }

    /// @notice Manually claim and distribute extra rewards for mainnet gauges
    function _claimAndDistributeExtraRewards(RewardVault vault, RewardReceiver receiver) internal {
        address gauge = vault.gauge();
        address[] memory extraTokens = vault.getRewardTokens();

        if (extraTokens.length == 0) return;

        // For mainnet, we need to manually trigger extra rewards claim
        // This simulates what would happen if the gauge had claimable rewards

        // Execute claim_rewards on the gauge via the gateway
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));
        bytes memory data = abi.encodeWithSignature("claim_rewards(address)", address(receiver));
        SafeLibrary.execOnLocker(payable(gateway), config.base.locker, gauge, data, signatures);

        // Now distribute the rewards from receiver to vault
        try receiver.distributeRewards() {}
        catch {
            // If distributeRewards fails, try distributing each token individually
            for (uint256 i = 0; i < extraTokens.length; i++) {
                try receiver.distributeRewardToken(IERC20(extraTokens[i])) {} catch {}
            }
        }
    }

    function simulateLockerRewards(address gauge, uint256 amount) internal {
        // Get current integrate_fraction (might be 0 or previously mocked)
        uint256 currentIntegrateFraction;
        try ILiquidityGauge(gauge).integrate_fraction(config.base.locker) returns (uint256 fraction) {
            currentIntegrateFraction = fraction;
        } catch {
            // If not mocked yet, start from current minted amount
            try IMinter(config.base.minter).minted(config.base.locker, gauge) returns (uint256 minted) {
                currentIntegrateFraction = minted;
            } catch {
                currentIntegrateFraction = 0;
            }
        }

        uint256 newIntegrateFraction = currentIntegrateFraction + amount;

        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, config.base.locker),
            abi.encode(newIntegrateFraction)
        );
    }

    /// @notice Setup extra reward tokens for mainnet gauges
    function _setupGaugeExtraRewards(address gauge) internal {
        // For mainnet, check if the gauge already has extra rewards
        // Store any existing extra rewards in our mapping

        address[] memory extraTokens = new address[](8); // Max 8 extra rewards
        uint256 tokenCount = 0;

        // Check for existing extra rewards
        for (uint256 i = 0; i < 8; i++) {
            try ILiquidityGauge(gauge).reward_tokens(i) returns (address token) {
                if (token == address(0)) break;
                extraTokens[tokenCount] = token;
                tokenCount++;
            } catch {
                break;
            }
        }

        // If no extra rewards exist, add a mock token for testing
        if (tokenCount == 0) {
            address mockToken = address(new ERC20Mock("Mock Reward", "RWRD", 18));
            extraTokens[0] = mockToken;
            tokenCount = 1;

            // Mock the reward token
            vm.mockCall(gauge, abi.encodeWithSelector(ILiquidityGauge.reward_tokens.selector, 0), abi.encode(mockToken));

            // Mock active reward period
            vm.mockCall(
                gauge,
                abi.encodeWithSelector(ILiquidityGauge.reward_data.selector, mockToken),
                abi.encode(
                    mockToken, // token
                    makeAddr("Distributor"), // distributor
                    block.timestamp + 1 days, // period_finish
                    1e18, // rate
                    block.timestamp, // last_update
                    0 // integral
                )
            );

            // Mock empty token for index 1
            vm.mockCall(
                gauge, abi.encodeWithSelector(ILiquidityGauge.reward_tokens.selector, 1), abi.encode(address(0))
            );
        }

        // Resize array and store
        assembly {
            mstore(extraTokens, tokenCount)
        }
        gaugeExtraTokens[gauge] = extraTokens;
    }

    /// @notice Simulate extra rewards for mainnet
    function _simulateExtraRewardForToken(RewardVault, address gauge, address token, uint256 amount)
        internal
        override
    {
        address rewardReceiver = protocolController.rewardReceiver(gauge);

        // Deal tokens to the gauge
        deal(token, gauge, IERC20(token).balanceOf(gauge) + amount);

        // Mock claimable rewards
        vm.mockCall(
            gauge,
            abi.encodeWithSelector(ILiquidityGauge.claimable_reward.selector, rewardReceiver, token),
            abi.encode(amount)
        );

        // Mint tokens to reward receiver to simulate claim
        vm.startPrank(gauge);
        ERC20Mock(token).mint(rewardReceiver, amount);
        vm.stopPrank();

        // Handle CVX rewards through sidecar
        if (token == config.convex.cvx) {
            address sidecar = ConvexSidecarFactory(sidecarFactory).sidecar(gauge);
            if (sidecar != address(0)) {
                address baseRewardPool = address(ConvexSidecar(sidecar).baseRewardPool());
                deal(token, baseRewardPool, IERC20(token).balanceOf(baseRewardPool) + amount);
            }
        }
    }
}
