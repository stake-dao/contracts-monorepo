// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "test/integration/curve/CurveIntegration.sol";
import {CurveLocker, CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IMinter} from "@interfaces/curve/IMinter.sol";

contract CurveMainnetIntegrationTest is CurveIntegration {
    using Math for uint256;

    function getConfig() internal view virtual returns (Config memory) {
        return Config({
            base: BaseConfig({
                chain: "mainnet",
                blockNumber: 22_311_339,
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
                convexBoostHolder: CurveProtocol.CONVEX_BOOSTER,
                booster: CurveProtocol.CONVEX_BOOSTER
            })
        });
    }

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

    constructor() CurveIntegration(getConfig()) {
        vm.label(CurveProtocol.CRV, "CRV");
        vm.label(CurveLocker.LOCKER, "Locker");
        vm.label(CurveProtocol.MINTER, "Minter");
        vm.label(CurveProtocol.VE_BOOST, "VE Boost");
        vm.label(CurveProtocol.GAUGE_CONTROLLER, "Gauge Controller");
        vm.label(CurveLocker.STRATEGY, "Strategy");
        vm.label(CurveProtocol.CONVEX_TOKEN, "CVX");
        vm.label(CurveProtocol.CONVEX_BOOSTER, "Booster");
    }

    function deployRewardVaults()
        internal
        override
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
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
}
