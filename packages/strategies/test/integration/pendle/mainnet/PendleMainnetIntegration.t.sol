// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PendleIntegration} from "test/integration/pendle/PendleIntegration.sol";
import {PendleProtocol, PendleLocker} from "@address-book/src/PendleEthereum.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardVault} from "src/RewardVault.sol";
import {IPendleGauge} from "src/interfaces/IPendleGauge.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";

/// @title PendleMainnetIntegrationTest
/// @notice Comprehensive integration test on Ethereum mainnet fork for Pendle markets
contract PendleMainnetIntegrationTest is PendleIntegration {
    using stdStorage for StdStorage;

    //////////////////////////////////////////////////////
    // --- CONSTANTS & CONFIGURATION
    //////////////////////////////////////////////////////

    Config public _config = Config({
        base: BaseConfig({
            chain: "mainnet",
            blockNumber: 22_982_312,
            rewardToken: PendleProtocol.PENDLE,
            locker: PendleLocker.LOCKER,
            protocolId: bytes4(keccak256("PENDLE")),
            harvestPolicy: IStrategy.HarvestPolicy.CHECKPOINT,
            gaugeController: PendleProtocol.GAUGE_CONTROLLER,
            oldStrategy: PendleLocker.STRATEGY
        })
    });

    constructor() PendleIntegration(_config) {
        vm.label(PendleLocker.LOCKER, "Locker");
        vm.label(PendleProtocol.PENDLE, "$PENDLE");
        vm.label(PendleProtocol.GAUGE_CONTROLLER, "GAUGE_CONTROLLER");
        vm.label(PendleLocker.STRATEGY, "OLD_STRATEGY");
    }

    function setUp() public override {
        super.setUp();

        /*
         * Pendle has no on-chain minter. Rewards come from tokens that already
         * sit inside each market and are streamed out over time. In prod those
         * tokens arrive weekly once via `GaugeController.redeemMarketReward()`,
         * but in this forked-mainnet integration test we don't execute that flow.
         *
         * To guarantee there is always sufficient inventory, we pre-fund every
         * market once during set-up. This keeps the test deterministic without
         * having to recalculate the gross amount (locker + fee) for every
         * simulated reward injection.
         */
        address[] memory gauges = getGauges();
        for (uint256 i; i < gauges.length; i++) {
            deal(_config.base.rewardToken, address(gauges[i]), 1e30);
        }
    }

    //////////////////////////////////////////////////////
    // --- OVERRIDES
    //////////////////////////////////////////////////////

    /// @dev Returns the set of markets (gauges) to be tested.
    function getGauges() internal override returns (address[] memory) {
        address[] memory gauges = new address[](5);
        gauges[0] = 0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2;
        vm.label(gauges[0], "PendleMarket (wstETH)");
        gauges[1] = 0xD4f6592DE90024e541187527d7F1dE83F6Cb6a52;
        vm.label(gauges[1], "PendleMarket (sGHO)");
        gauges[2] = 0x55F06992E4C3ed17Df830dA37644885c0c34EDdA;
        vm.label(gauges[2], "PendleMarket (RLP)");
        gauges[3] = 0x45F163E583D34b8E276445dd3Da9aE077D137d72;
        vm.label(gauges[3], "PendleMarket (sUSDf)");
        gauges[4] = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;
        vm.label(gauges[4], "PendleMarket (sUSDe)");
        return gauges;
    }

    /// @notice Simulates rewards for the given vault by bumping the internal accounting.
    /// @dev The Pendle gauge code stores:
    ///         - mapping(address => RewardState) public rewardState;           // (index, lastBalance)
    ///         - mapping(address => mapping(address => UserReward)) public userReward; // (index, accrued)
    /// Meaning we need to update:
    ///         - rewardState[PENDLE].lastBalance    += amount;
    ///         - userReward[PENDLE][LOCKER].accrued += amount;
    function simulateRewards(RewardVault vault, uint256 amount) internal override {
        IPendleGauge gauge = IPendleGauge(vault.gauge());
        address locker = _config.base.locker;
        address pendle = _config.base.rewardToken;

        // Update the global reward accounting. The targetted storage slot stores a packed struct.
        IPendleGauge.RewardState memory currentState = gauge.rewardState(pendle);
        uint256 currentStateSlot =
            stdstore.enable_packed_slots().target(address(gauge)).sig("rewardState(address)").with_key(pendle).find();
        vm.store(
            address(gauge),
            bytes32(currentStateSlot),
            bytes32(_pack(currentState.index, currentState.lastBalance + uint128(amount)))
        );

        // Update the accounting of the locker. The targetted storage slot stores a packed struct.
        IPendleGauge.UserReward memory currentUserReward = gauge.userReward(pendle, locker);
        uint256 currentUserRewardSlot = stdstore.enable_packed_slots().target(address(gauge)).sig(
            "userReward(address,address)"
        ).with_key(pendle).with_key(locker).find();
        vm.store(
            address(gauge),
            bytes32(currentUserRewardSlot),
            bytes32(_pack(currentUserReward.index, currentUserReward.accrued + uint128(amount)))
        );
    }

    /// @dev Pack two uint128 values into a single uint256 storage slot.
    /// @param firstValue The value that is stored first in the struct.
    /// @param secondValue The value that is stored second in the struct.
    function _pack(uint128 firstValue, uint128 secondValue) internal pure returns (uint256) {
        return (uint256(secondValue) << 128) | uint256(firstValue);
    }
}
