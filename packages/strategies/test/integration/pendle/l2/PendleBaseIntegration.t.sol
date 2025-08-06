// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PendleIntegration} from "test/integration/pendle/PendleIntegration.sol";
import {PendleProtocol} from "@address-book/src/PendleBase.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {RewardVault} from "src/RewardVault.sol";
import {IPendleGauge} from "src/interfaces/IPendleGauge.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PendleBaseIntegrationTest
/// @notice Comprehensive integration test on Base fork for Pendle markets
contract PendleBaseIntegrationTest is PendleIntegration {
    using stdStorage for StdStorage;

    //////////////////////////////////////////////////////
    // --- CONSTANTS & CONFIGURATION
    //////////////////////////////////////////////////////

    Config public _config = Config({
        base: BaseConfig({
            chain: "base",
            blockNumber: 33_332_516,
            rewardToken: PendleProtocol.PENDLE,
            locker: address(0),
            protocolId: bytes4(keccak256("PENDLE")),
            harvestPolicy: IStrategy.HarvestPolicy.HARVEST,
            gaugeController: PendleProtocol.GAUGE_CONTROLLER,
            oldStrategy: address(0)
        })
    });

    constructor() PendleIntegration(_config) {
        vm.label(PendleProtocol.PENDLE, "$PENDLE");
        vm.label(PendleProtocol.GAUGE_CONTROLLER, "GAUGE_CONTROLLER");
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
        gauges[0] = 0xa46caC2243Ecd83A6a9Ad58232C1967EBD14D41B;
        vm.label(gauges[0], "PendleMarket (sKAITO)");
        gauges[1] = 0x715509Bde846104cF2cCeBF6fdF7eF1BB874Bc45;
        vm.label(gauges[1], "PendleMarket (USR)");
        gauges[2] = 0x6144511E1BD935c258B7b9075F120474dF1b1e5f;
        vm.label(gauges[2], "PendleMarket (aGHO)");
        gauges[3] = 0x483f2e223c58a5eF19c4B32fbC6dE57709749cb3;
        vm.label(gauges[3], "PendleMarket (cbETH)");
        gauges[4] = 0xD5dD84c7b8919DceB09536a0FEf6db9046805127;
        vm.label(gauges[4], "PendleMarket (rETH)");
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

        _cheat_rewards(address(gauge), config.base.rewardToken, amount);
    }

    function _simulateExtraRewardForToken(RewardVault, address gauge, address token, uint256 amount)
        internal
        override
    {
        if (token == PendleProtocol.PENDLE) return;

        // Direct storage manipulation
        _cheat_rewards(gauge, token, amount);

        // Ensure the gauge has tokens to distribute
        deal(token, address(gauge), IERC20(token).balanceOf(address(gauge)) + amount);
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Direct storage manipulation of the Pendle gauge rewards to simulate rewards.
    /// @dev The Pendle gauge code stores:
    ///         - mapping(address => RewardState) public rewardState;           // (index, lastBalance)
    ///         - mapping(address => mapping(address => UserReward)) public userReward; // (index, accrued)
    /// Meaning we need to update:
    ///         - rewardState[TOKEN].lastBalance    += amount;
    ///         - userReward[TOKEN][LOCKER].accrued += amount;
    /// @param gauge The address of the Pendle gauge.
    /// @param token The address of the reward token.
    /// @param amount The amount of reward tokens to simulate.
    function _cheat_rewards(address gauge, address token, uint256 amount) internal {
        address locker = config.base.locker == address(0) ? address(gateway) : config.base.locker;

        // 1. Update reward state
        IPendleGauge.RewardState memory currentState = IPendleGauge(gauge).rewardState(token);
        uint256 rewardStateSlot =
            stdstore.enable_packed_slots().target(address(gauge)).sig("rewardState(address)").with_key(token).find();
        vm.store(
            address(gauge),
            bytes32(rewardStateSlot),
            bytes32(_pack(currentState.index, currentState.lastBalance + uint128(amount)))
        );

        // 2. Update user accounting
        IPendleGauge.UserReward memory currentUserReward = IPendleGauge(gauge).userReward(token, locker);
        uint256 userRewardSlot = stdstore.enable_packed_slots().target(gauge).sig("userReward(address,address)")
            .with_key(token).with_key(locker).find();
        vm.store(
            gauge,
            bytes32(userRewardSlot),
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
