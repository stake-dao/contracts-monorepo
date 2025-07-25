// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SafeLibrary} from "test/utils/SafeLibrary.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {PendleFactory} from "src/integrations/pendle/PendleFactory.sol";
import {PendleStrategy} from "src/integrations/pendle/PendleStrategy.sol";
import {IPendleStrategy} from "@interfaces/stake-dao/IPendleStrategy.sol";
import {PendleAllocator} from "src/integrations/pendle/PendleAllocator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.sol";

/// @title PendleIntegration - Integration Test Base for Pendle protocol
abstract contract PendleIntegration is BaseIntegrationTest {
    //////////////////////////////////////////////////////
    // --- CONFIGURATION STRUCTS
    //////////////////////////////////////////////////////

    /// @notice Base configuration for the test.
    struct BaseConfig {
        string chain; // RPC/Fork identifier (e.g. "mainnet")
        bytes4 protocolId; // Protocol identifier used in Stake DAO V2
        uint256 blockNumber; // Fork block number
        address locker; // Locker address holding LP & vePENDLE
        address rewardToken; // PENDLE token address
        IStrategy.HarvestPolicy harvestPolicy; // Harvest policy (CHECKPOINT or HARVEST)
        address gaugeController; // Pendle Gauge Controller
        address oldStrategy; // Address of legacy strategy (v1)
    }

    /// @notice Combined configuration for the test (single struct for now, but mirrors Curve pattern).
    struct Config {
        BaseConfig base;
    }

    /// @notice Public test configuration instance.
    Config public config;

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR & SETUP
    //////////////////////////////////////////////////////

    constructor(Config memory _config) {
        config = _config;
    }

    /// @notice Deploys core contracts and prepares the environment.
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

        /// 2. Deploy the Pendle Strategy contract.
        strategy = address(
            new PendleStrategy({
                _registry: address(protocolController),
                _locker: config.base.locker,
                _gateway: address(gateway)
            })
        );

        /// 3. Deploy the Pendle Allocator contract.
        allocator = new PendleAllocator(config.base.locker, address(gateway));

        /// 4. Untach the gauges from the old strategy if needed
        _detachGaugesFromOldStrategy();

        /// 5. Deploy the Pendle Factory contract.
        factory = address(
            new PendleFactory(
                config.base.gaugeController,
                config.base.oldStrategy,
                address(protocolController),
                address(rewardVaultImplementation),
                address(rewardReceiverImplementation),
                config.base.locker,
                address(gateway)
            )
        );

        ////////////////////////////////////////////////////
        // 5. Clean locker balances to ensure deterministic state
        ////////////////////////////////////////////////////
        _clearLockerBalances();
    }

    //////////////////////////////////////////////////////
    // --- INTERNAL HELPERS
    //////////////////////////////////////////////////////

    /// @dev Removes any pre-existing LP/gauge token balances from the locker to avoid interference with tests.
    function _clearLockerBalances() internal {
        for (uint256 i; i < gauges.length; i++) {
            uint256 balance = IERC20(gauges[i]).balanceOf(config.base.locker);
            if (balance == 0) continue;

            // Build Safe signatures (single admin owner)
            bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

            // Simply transfer LP tokens to a burn address. Holding = staked in Pendle.
            bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", burnAddress, balance);
            SafeLibrary.execOnLocker(payable(gateway), config.base.locker, gauges[i], data, signatures);
        }
    }

    function _detachGaugesFromOldStrategy() internal {
        if (config.base.oldStrategy == address(0)) return;
        for (uint256 i; i < gauges.length; i++) {
            address gauge = gauges[i];
            address governance = IPendleStrategy(config.base.oldStrategy).governance();

            if (IPendleStrategy(config.base.oldStrategy).sdGauges(gauge) != address(0)) {
                vm.prank(governance);
                IPendleStrategy(config.base.oldStrategy).setSdGauge(gauge, address(0));
            }
        }
    }
}
